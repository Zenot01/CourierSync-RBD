-- Włączenie opcji Ad Hoc w celu możliwości użycia OPENROWSET
EXEC sys.sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sys.sp_configure 'Ad Hoc Distributed Queries', 1;
RECONFIGURE;
GO

-- Warszawa
CREATE LOGIN CentralAdminLogin WITH PASSWORD = 'HQAdminPassword123!';
CREATE LOGIN AppCentralLogin WITH PASSWORD = 'HQAppPassword123!';

USE WarszawaHQ;

CREATE USER COURIER_HQ_ADMIN FOR LOGIN CentralAdminLogin;
CREATE USER COURIER_HQ_APP FOR LOGIN AppCentralLogin;

-- Nadanie uprawnień administracyjnych/aplikacyjnych w bazie
ALTER ROLE db_owner ADD MEMBER COURIER_HQ_ADMIN;
ALTER ROLE db_datawriter ADD MEMBER COURIER_HQ_APP;
ALTER ROLE db_datareader ADD MEMBER COURIER_HQ_APP;

USE [master];
GO

EXEC sys.sp_addlinkedserver   
   @server = N'SQLSRV-REG',   
   @srvproduct = N'SQL Server',
   @provider = N'MSOLEDBSQL',   
   @datasrc = N'KRAKOW_HQ';
GO

EXEC sys.sp_addlinkedsrvlogin   
   @rmtsrvname = N'SQLSRV-REG',   
   @useself = N'False',
   @rmtuser = N'LinkedServerLogin',
   @rmtpassword = N'REGLinkedPassword123!';
GO

-- Włączenie RPC i RPC Out dla SQLSRV-REG (wymagane do zdalnych procedur w transakcjach)
EXEC sys.sp_serveroption @server=N'SQLSRV-REG', @optname=N'rpc', @optvalue=N'true';
EXEC sys.sp_serveroption @server=N'SQLSRV-REG', @optname=N'rpc out', @optvalue=N'true';
GO

-- test polaczenia
EXEC sys.sp_testlinkedserver N'SQLSRV-REG';
GO

EXEC sys.sp_addlinkedserver   
   @server = N'ORA-ACCT',   
   @srvproduct = N'Oracle',   
   @provider = N'OraOLEDB.Oracle',   
   @datasrc = N'XE'; 
GO

-- Mapowanie loginów lokalnych na zdalne w Oracle (polityka ról)
-- 1. Mapowanie administratora na konto z pełnymi prawami
EXEC sys.sp_addlinkedsrvlogin   
   @rmtsrvname = N'ORA-ACCT',   
   @useself = N'False',
   @locallogin = N'COURIER_HQ_ADMIN',
   @rmtuser = N'COURIER_ADMIN',          
   @rmtpassword = N'AdminSecure123!';  
GO

-- 2. Mapowanie aplikacji na konto z prawami zapisu/odczytu faktur
EXEC sys.sp_addlinkedsrvlogin   
   @rmtsrvname = N'ORA-ACCT',   
   @useself = N'False',
   @locallogin = N'COURIER_HQ_APP',
   @rmtuser = N'COURIER_APP',          
   @rmtpassword = N'AppSecure123!';  
GO

-- 3. Domyślne mapowanie dla pozostałych użytkowników (tylko do odczytu)
EXEC sys.sp_addlinkedsrvlogin   
   @rmtsrvname = N'ORA-ACCT',   
   @useself = N'False',
   @locallogin = NULL,   
   @rmtuser = N'COURIER_RO',          
   @rmtpassword = N'ROSecure123!';  
GO

-- Włączenie RPC i RPC Out dla ORA-ACCT (wymagane do zdalnego wywoływania PL/SQL)
EXEC sys.sp_serveroption @server=N'ORA-ACCT', @optname=N'rpc', @optvalue=N'true';
EXEC sys.sp_serveroption @server=N'ORA-ACCT', @optname=N'rpc out', @optvalue=N'true';
GO

-- Weryfikacja dostępności połączenia
EXEC sys.sp_testlinkedserver N'ORA-ACCT';
GO

-- Dodanie serwera połączonego MS Access (ACC-LOCAL)
EXEC sys.sp_addlinkedserver   
   @server = N'ACC-LOCAL',   
   @srvproduct = N'Access',   
   @provider = N'Microsoft.ACE.OLEDB.12.0',   
   @datasrc = N'C:\CourierSync\Database\LocalNadania.accdb';
GO

-- Dodanie serwera połączonego MS Excel (XLS-RAPORTY)
EXEC sys.sp_addlinkedserver   
   @server = N'XLS-RAPORTY',   
   @srvproduct = N'Excel',   
   @provider = N'Microsoft.ACE.OLEDB.12.0',   
   @datasrc = N'C:\CourierSync\Reports\MonthlyReport.xlsx',
   @provstr = N'Excel 12.0 XML;HDR=YES';
GO

USE WarszawaHQ;

-- Tabela: Oddzialy
CREATE TABLE Oddzialy (
    IdOddzialu INT IDENTITY(1,1) PRIMARY KEY,
    Nazwa VARCHAR(100) NOT NULL,
    Miasto VARCHAR(50) NOT NULL
);

-- Tabela: Sortownie
CREATE TABLE Sortownie (
    IdSortowni INT IDENTITY(1,1) PRIMARY KEY,
    NazwaSortowni VARCHAR(100) NOT NULL,
    KodSortowni VARCHAR(20) NOT NULL UNIQUE,
    IdOddzialu INT FOREIGN KEY REFERENCES Oddzialy(IdOddzialu)
);

-- Tabela: Pracownicy
CREATE TABLE Pracownicy (
    IdPracownika INT IDENTITY(1,1) PRIMARY KEY,
    Imie VARCHAR(50) NOT NULL,
    Nazwisko VARCHAR(50) NOT NULL,
    Stanowisko VARCHAR(50) NOT NULL,
    IdOddzialu INT FOREIGN KEY REFERENCES Oddzialy(IdOddzialu)
);

-- Tabela: Klienci
CREATE TABLE Klienci (
    IdKlienta INT IDENTITY(1,1) PRIMARY KEY,
    NazwaFirmy_ImieNazwisko VARCHAR(150) NOT NULL,
    NIP VARCHAR(10) NULL,
    Adres VARCHAR(200) NOT NULL,
    Telefon VARCHAR(15) NOT NULL
);

-- Tabela: Zamowienia
CREATE TABLE Zamowienia (
    IdZamowienia INT IDENTITY(1,1) PRIMARY KEY,
    IdKlienta INT FOREIGN KEY REFERENCES Klienci(IdKlienta),
    DataZlozenia DATETIME DEFAULT GETDATE(),
    StatusZamowienia VARCHAR(30) DEFAULT 'PRZYJETE'
);

-- Tabela: Przesylki
CREATE TABLE Przesylki (
    IdPrzesylki INT IDENTITY(1,1) PRIMARY KEY,
    IdZamowienia INT FOREIGN KEY REFERENCES Zamowienia(IdZamowienia),
    IdKlientaNadawcy INT FOREIGN KEY REFERENCES Klienci(IdKlienta),
    IdKlientaOdbiorcy INT FOREIGN KEY REFERENCES Klienci(IdKlienta),
    TypPrzesylki VARCHAR(30) DEFAULT 'STANDARD',
    Waga DECIMAL(10,2) NULL, -- Waga przesyłki używana do wyceny
    IdPrzesylkiOryginalnej INT FOREIGN KEY REFERENCES Przesylki(IdPrzesylki),
    WyliczonaOplata DECIMAL(10,2) NULL, -- Uzupełniane przez procedurę usp_WycenPrzesylke
    StatusPrzesylki VARCHAR(30)
);

GO

-- =========================================================================
-- PROCEDURY SKŁADOWANE (WARSZAWA CENTRALNY WĘZEŁ) - ETAP 1
-- =========================================================================

-- =========================================================================
-- 2. usp_WycenPrzesylke
-- Pobiera cennik z serwera Oracle przy użyciu OPENQUERY,
-- oblicza opłatę na podstawie typu przesyłki oraz wagi,
-- i zapisuje ją w tabeli lokalnej.
-- =========================================================================
CREATE PROCEDURE usp_WycenPrzesylke
    @IdPrzesylki INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TypPrzesylki VARCHAR(30);
    DECLARE @Waga DECIMAL(10,2);

    -- Pobranie typu przesyłki i wagi
    SELECT 
        @TypPrzesylki = TypPrzesylki,
        @Waga = ISNULL(Waga, 1.0)
    FROM Przesylki
    WHERE IdPrzesylki = @IdPrzesylki;

    IF @TypPrzesylki IS NULL
    BEGIN
        RAISERROR('Przesyłka o podanym ID nie istnieje.', 16, 1);
        RETURN;
    END

    DECLARE @CenaBazowa DECIMAL(10,2);
    DECLARE @CenaZaKg DECIMAL(10,2);

    -- Pobranie cennika z Oracle za pomocą zapytania ad-hoc OPENROWSET
    SELECT TOP 1 
        @CenaBazowa = CAST(cena_bazowa AS DECIMAL(10,2)),
        @CenaZaKg = CAST(ISNULL(cena_za_kg, 0) AS DECIMAL(10,2))
    FROM OPENROWSET('OraOLEDB.Oracle', 'XE';'COURIER_RO';'ROSecure123!', 'SELECT nazwa_uslugi, cena_bazowa, cena_za_kg FROM Cennik')
    WHERE UPPER(nazwa_uslugi) = UPPER(@TypPrzesylki);

    -- Obsługa przypadku braku dopasowania - pobranie ceny standardowej
    IF @CenaBazowa IS NULL
    BEGIN
        SELECT TOP 1 
            @CenaBazowa = CAST(cena_bazowa AS DECIMAL(10,2)),
            @CenaZaKg = CAST(ISNULL(cena_za_kg, 0) AS DECIMAL(10,2))
        FROM OPENROWSET('OraOLEDB.Oracle', 'XE';'COURIER_RO';'ROSecure123!', 'SELECT nazwa_uslugi, cena_bazowa, cena_za_kg FROM Cennik')
        WHERE UPPER(nazwa_uslugi) = 'STANDARD';
    END

    -- Wyliczenie i zapis opłaty
    DECLARE @WyliczonaOplata DECIMAL(10,2) = @CenaBazowa + (@Waga * @CenaZaKg);

    UPDATE Przesylki
    SET WyliczonaOplata = @WyliczonaOplata
    WHERE IdPrzesylki = @IdPrzesylki;

    PRINT 'Wyceniono przesyłkę: opłata wynosi ' + CAST(@WyliczonaOplata AS VARCHAR(20));
END;
GO

-- =========================================================================
-- 3. usp_OdswiezRaportXLS
-- Pobiera niezaimportowane zlecenia z lokalnej bazy MS Access (ACC-LOCAL)
-- filtrując je po dacie, łączy z lokalną tabelą Zamowienia
-- i wstawia nowe rekordy, oznaczając zaimportowane w Access jako Zaimportowane = 1.
-- Posiada obsługę błędów na wypadek braku dostępności Access.
-- =========================================================================
CREATE PROCEDURE usp_OdswiezRaportXLS
    @DataGraniczna DATETIME = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @DataGraniczna IS NULL
        SET @DataGraniczna = '2000-01-01';

    BEGIN TRY
        -- Sprawdzenie dostępności serwera połączonego
        EXEC sys.sp_testlinkedserver N'ACC-LOCAL';

        -- Wstawienie nowych zamówień
        INSERT INTO Zamowienia (IdKlienta, DataZlozenia, StatusZamowienia)
        SELECT 
            src.IdKlienta,
            src.DataNadania,
            'PRZYJETE'
        FROM OPENQUERY([ACC-LOCAL], 'SELECT IdNadania, IdKlienta, DataNadania, Zaimportowane FROM Nadania WHERE Zaimportowane = 0') src
        WHERE src.DataNadania >= @DataGraniczna
          AND NOT EXISTS (
              SELECT 1 
              FROM Zamowienia z 
              WHERE z.IdKlienta = src.IdKlienta 
                AND z.DataZlozenia = src.DataNadania
          );

        -- Aktualizacja statusu zaimportowania w bazie Access za pomocą OPENQUERY
        UPDATE OPENQUERY([ACC-LOCAL], 'SELECT Zaimportowane FROM Nadania WHERE Zaimportowane = 0')
        SET Zaimportowane = 1;

        PRINT 'Pomyślnie zaimportowano zamówienia z bazy Access.';
    END TRY
    BEGIN CATCH
        -- Obsługa braku połączenia / błędów bazy Access bez przerywania działania innych procesów
        DECLARE @Msg NVARCHAR(4000) = 'Błąd podczas importu z Access: ' + ERROR_MESSAGE();
        PRINT @Msg;
    END CATCH
END;
GO

-- =========================================================================
-- PROCEDURY SKŁADOWANE (WARSZAWA CENTRALNY WĘZEŁ) - ETAP 2 (TRANSAKCJE)
-- =========================================================================

-- =========================================================================
-- 1. usp_PotwierdzDoreczenie
-- Główna procedura transakcji rozproszonej koordynowana przez MS DTC.
-- Aktualizuje status w centrali, rejestruje zdarzenie w oddziale
-- oraz wystawia fakturę w Oracle.
-- =========================================================================
CREATE PROCEDURE usp_PotwierdzDoreczenie
    @IdPrzesylki INT,
    @IdKuriera INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON; -- Krytyczne dla prawidłowego działania transakcji rozproszonych

    -- Pobranie informacji o przesyłce i opłacie
    DECLARE @IdKlienta INT;
    DECLARE @KwotaBrutto DECIMAL(10,2);
    
    SELECT 
        @IdKlienta = IdKlientaNadawcy,
        @KwotaBrutto = WyliczonaOplata
    FROM Przesylki
    WHERE IdPrzesylki = @IdPrzesylki;

    IF @IdKlienta IS NULL
    BEGIN
        RAISERROR('Przesyłka o podanym ID nie istnieje lub nie posiada nadawcy.', 16, 1);
        RETURN;
    END

    IF @KwotaBrutto IS NULL OR @KwotaBrutto <= 0
    BEGIN
        -- Wywołanie wyceny jako fallback, jeśli przesyłka nie została wyceniona
        EXEC usp_WycenPrzesylke @IdPrzesylki = @IdPrzesylki;
        SELECT @KwotaBrutto = WyliczonaOplata FROM Przesylki WHERE IdPrzesylki = @IdPrzesylki;
    END

    -- Obliczenie wartości netto i VAT
    DECLARE @KwotaNetto DECIMAL(10,2) = ROUND(@KwotaBrutto / 1.23, 2);
    DECLARE @KwotaVat DECIMAL(10,2) = @KwotaBrutto - @KwotaNetto;
    
    -- Wygenerowanie unikalnego numeru faktury
    DECLARE @NumerFaktury VARCHAR(50) = 'FV/' + CAST(@IdPrzesylki AS VARCHAR) + '/' + CONVERT(VARCHAR(8), GETDATE(), 112);

    -- Pobranie IdSortowni powiązanej z kurierem (lub pierwszej dostępnej)
    DECLARE @IdSortowni INT;
    SELECT TOP 1 @IdSortowni = s.IdSortowni
    FROM Sortownie s
    JOIN Pracownicy p ON s.IdOddzialu = p.IdOddzialu
    WHERE p.IdPracownika = @IdKuriera;

    IF @IdSortowni IS NULL
    BEGIN
        SELECT TOP 1 @IdSortowni = IdSortowni FROM Sortownie;
    END

    -- Rozpoczęcie transakcji rozproszonej (MS DTC)
    BEGIN DISTRIBUTED TRANSACTION;

    BEGIN TRY
        -- Krok A: Aktualizacja statusu przesyłki w centrali (lokalnie)
        UPDATE Przesylki
        SET StatusPrzesylki = 'Dostarczona'
        WHERE IdPrzesylki = @IdPrzesylki;

        -- Krok B: Zapis zdarzenia logistycznego w oddziale regionalnym przez Linked Server
        EXEC [SQLSRV-REG].KrakowHQ.dbo.usp_ZapiszZdarzenieLogistyczne 
            @IdPrzesylki = @IdPrzesylki,
            @KodZdarzenia = 'DORECZONO',
            @IdKuriera = @IdKuriera,
            @IdSortowni = @IdSortowni;

        -- Krok C: Wystawienie faktury w Oracle przez RPC i Linked Server
        DECLARE @Sql NVARCHAR(MAX) = N'BEGIN COURIER_ADMIN.usp_WystawFakture(?, ?, ?, ?, ?, ?); END;';
        EXEC (@Sql, @IdKlienta, @NumerFaktury, @KwotaNetto, @KwotaVat, @KwotaBrutto, @IdPrzesylki) AT [ORA-ACCT];

        -- Zatwierdzenie transakcji rozproszonej na wszystkich węzłach
        COMMIT TRANSACTION;
        PRINT 'Dostarczenie przesyłki potwierdzone i zafakturowane pomyślnie.';
    END TRY
    BEGIN CATCH
        -- Wycofanie transakcji w przypadku jakiegokolwiek błędu na dowolnym węźle
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH
END;
GO

-- =========================================================================
-- WIDOKI ROZPROSZONE (WIELODOSTĘP DO RÓŻNYCH ŹRÓDEŁ DANYCH - ORACLE, ACCESS, EXCEL)
-- =========================================================================
-- Widok integruje w jednym miejscu dane z centrali, faktury z Oracle,
-- lokalne nadania z bazy Access oraz raporty miesięczne z Excela.
-- =========================================================================
CREATE VIEW vw_KonsolidacjaRaportu AS
SELECT 
    p.IdPrzesylki,
    p.StatusPrzesylki,
    p.WyliczonaOplata,
    -- Dane z Oracle (Linked Server ORA-ACCT)
    f.numer_faktury AS Oracle_NumerFaktury,
    f.kwota_brutto AS Oracle_KwotaBrutto,
    -- Dane z Access (Linked Server ACC-LOCAL)
    a.IdNadania AS Access_IdNadania,
    a.DataNadania AS Access_DataNadania,
    -- Dane z Excela (Linked Server XLS-RAPORTY)
    e.SumaDostaw AS Excel_SumaDostaw,
    e.Miesiac AS Excel_Miesiac
FROM Przesylki p
LEFT JOIN [ORA-ACCT]..COURIER_RO.FAKTURY f ON p.IdPrzesylki = f.id_przesylki
LEFT JOIN [ACC-LOCAL]...Nadania a ON p.IdKlientaNadawcy = a.IdKlienta
LEFT JOIN [XLS-RAPORTY]...[Sheet1$] e ON e.Miesiac = CONVERT(VARCHAR(7), GETDATE(), 120);
GO

