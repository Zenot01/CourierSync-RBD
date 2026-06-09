-- Kraków
-- Loginy muszą być tworzone w kontekście bazy master
USE [master];
GO

CREATE LOGIN RegionalAdminLogin WITH PASSWORD = 'REGAdminPassword123!';
CREATE LOGIN LinkedServerLogin WITH PASSWORD = 'REGLinkedPassword123!';
GO

USE KrakowHQ;

CREATE USER COURIER_REG_ADMIN FOR LOGIN RegionalAdminLogin;
CREATE USER COURIER_LINKED_HQ FOR LOGIN LinkedServerLogin;

ALTER ROLE db_owner ADD MEMBER COURIER_REG_ADMIN;
ALTER ROLE db_datawriter ADD MEMBER COURIER_LINKED_HQ;
ALTER ROLE db_datareader ADD MEMBER COURIER_LINKED_HQ;

-- Tabela: Pojazdy
CREATE TABLE Pojazdy (
    IdPojazdu INT IDENTITY(1,1) PRIMARY KEY,
    NrRejestracyjny VARCHAR(15) NOT NULL UNIQUE,
    Marka VARCHAR(50),
    Model VARCHAR(50)
);

-- Tabela: Trasy
CREATE TABLE Trasy (
    IdTrasy INT IDENTITY(1,1) PRIMARY KEY,
    NazwaTrasy VARCHAR(100) NOT NULL,
    OpisStrefy VARCHAR(250)
);

-- Tabela: EtapyTrasy (kolejność przystanków na trasie)
CREATE TABLE EtapyTrasy (
    IdEtapu INT IDENTITY(1,1) PRIMARY KEY,
    IdTrasy INT FOREIGN KEY REFERENCES Trasy(IdTrasy),
    IdSortowni INT NOT NULL, -- Logiczne powiązanie z HQ_Sortownie
    KolejnoscRozladunku INT NOT NULL, -- Kolejny numer przystanku na trasie (np. 1, 2, 3)
    CONSTRAINT UC_TrasaKolejnosc UNIQUE (IdTrasy, KolejnoscRozladunku)
);

-- Tabela: PrzydzialyKurierow
CREATE TABLE PrzydzialyKurierow (
    IdPrzydzialu INT IDENTITY(1,1) PRIMARY KEY,
    IdKuriera INT NOT NULL, -- IdPracownika pobierane logicznie z HQ przez replikację/widok
    IdPojazdu INT FOREIGN KEY REFERENCES Pojazdy(IdPojazdu),
    IdTrasy INT FOREIGN KEY REFERENCES Trasy(IdTrasy),
    DataPrzydzialu DATE DEFAULT CAST(GETDATE() AS DATE)
);

-- Tabela: ZaladunekPojazdu (manifest załadunkowy LIFO)
CREATE TABLE ZaladunekPojazdu (
    IdZaladunku INT IDENTITY(1,1) PRIMARY KEY,
    IdPrzydzialu INT FOREIGN KEY REFERENCES PrzydzialyKurierow(IdPrzydzialu),
    IdPrzesylki INT NOT NULL, -- Logiczne powiązanie z tabelą Przesylki w HQ
    KolejnoscZaladunku INT NOT NULL, -- Wyliczona kolejność ładowania paczki
    SektorTira VARCHAR(20) NULL -- np. 'PRZOD', 'SRODEK', 'TYL'
);

-- Tabela: ZdarzeniaLogistyczne
CREATE TABLE ZdarzeniaLogistyczne (
    IdZdarzenia INT IDENTITY(1,1) PRIMARY KEY,
    IdPrzesylki INT NOT NULL, -- Logiczne powiązanie z tabelą Przesylki w HQ
    KodZdarzenia VARCHAR(20) NOT NULL, -- np. 'DORECZONO', 'W_TRASIE'
    IdKuriera INT NOT NULL,
    IdSortowni INT NOT NULL, -- Logiczne powiązanie z tabelą Sortownie w HQ
    DataZdarzenia DATETIME DEFAULT GETDATE()
);

-- Unikalny indeks zapobiegający duplikatom
CREATE UNIQUE INDEX UIDX_Zdarzenia_ZapobieganieDuplikatom 
ON ZdarzeniaLogistyczne (IdPrzesylki, KodZdarzenia, DataZdarzenia);

GO

-- =========================================================================
-- PROCEDURY SKŁADOWANE (KRAKÓW ODDZIAŁ REGIONALNY)
-- =========================================================================

-- =========================================================================
-- 1. usp_ZapiszZdarzenieLogistyczne
-- Zapisuje zdarzenie logistyczne w lokalnej bazie.
-- Zabezpieczona przed duplikatem za pomocą warunku EXISTS.
-- =========================================================================
CREATE PROCEDURE usp_ZapiszZdarzenieLogistyczne
    @IdPrzesylki INT,
    @KodZdarzenia VARCHAR(20),
    @IdKuriera INT,
    @IdSortowni INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Sprawdzenie, czy takie same zdarzenie już zostało zapisane w bieżącym dniu
    -- w celu uniknięcia naruszenia unikalnego indeksu UIDX_Zdarzenia_ZapobieganieDuplikatom
    IF NOT EXISTS (
        SELECT 1 
        FROM ZdarzeniaLogistyczne 
        WHERE IdPrzesylki = @IdPrzesylki 
          AND KodZdarzenia = @KodZdarzenia 
          AND CAST(DataZdarzenia AS DATE) = CAST(GETDATE() AS DATE)
    )
    BEGIN
        INSERT INTO ZdarzeniaLogistyczne (IdPrzesylki, KodZdarzenia, IdKuriera, IdSortowni, DataZdarzenia)
        VALUES (@IdPrzesylki, @KodZdarzenia, @IdKuriera, @IdSortowni, GETDATE());
        
        PRINT 'Zapisano zdarzenie logistyczne: ' + @KodZdarzenia;
    END
    ELSE
    BEGIN
        PRINT 'Zdarzenie logistyczne: ' + @KodZdarzenia + ' już istnieje dla tej przesyłki dzisiaj. Pominięto.';
    END
END;
GO

-- =========================================================================
-- 2. usp_OptymalizujTrase
-- Wyznacza optymalną trasę kuriera i generuje manifest załadunkowy (LIFO).
--
-- Działanie:
--   1. Pobiera aktywny przydział kuriera na dziś (trasa + pojazd).
--   2. Pobiera nieodebrane przesyłki kuriera z centralnej bazy HQ przez
--      Linked Server [SQLSRV-HQ], łącząc je z etapami trasy wg strefy doręczenia (IdSortowni).
--   3. Usuwa poprzedni manifest załadunkowy dla danego przydział, jeśli istnieje.
--   4. Generuje nowy manifest w tabeli ZaladunekPojazdu zgodnie z regułą LIFO:
--      - Paczki z OSTATNIEGO przystanku trasy → załadowane JAKO PIERWSZE → sektor TYŁ
--      - Paczki z PIERWSZEGO przystanku trasy → załadowane JAKO OSTATNIE → sektor PRZÓD
--   5. Zwraca gotowy manifest jako wynik SELECT.
-- =========================================================================
CREATE PROCEDURE usp_OptymalizujTrase
    @IdKuriera INT
AS
BEGIN
    SET NOCOUNT ON;

    -- === KROK 1: Pobierz aktywny przydział kuriera na dziś ===
    DECLARE @IdPrzydzialu INT;
    DECLARE @IdTrasy INT;
    DECLARE @LiczbaEtapow INT;

    SELECT TOP 1
        @IdPrzydzialu = pk.IdPrzydzialu,
        @IdTrasy      = pk.IdTrasy
    FROM PrzydzialyKurierow pk
    WHERE pk.IdKuriera = @IdKuriera
      AND pk.DataPrzydzialu = CAST(GETDATE() AS DATE)
    ORDER BY pk.IdPrzydzialu DESC;

    IF @IdPrzydzialu IS NULL
    BEGIN
        RAISERROR('Brak aktywnego przydziału kuriera %d na dziś.', 16, 1, @IdKuriera);
        RETURN;
    END;

    -- === KROK 2: Sprawdź liczbę etapów trasy ===
    SELECT @LiczbaEtapow = COUNT(*)
    FROM EtapyTrasy
    WHERE IdTrasy = @IdTrasy;

    IF @LiczbaEtapow = 0
    BEGIN
        RAISERROR('Trasa %d nie ma zdefiniowanych żadnych etapów (przystanków).', 16, 1, @IdTrasy);
        RETURN;
    END;

    -- === KROK 3: Pobierz nieodebrane przesyłki kuriera z HQ przez Linked Server ===
    -- OPENQUERY nie obsługuje parametrów lokalnych, dlatego budujemy zapytanie dynamicznie.
    -- Wynik trafia najpierw do tabeli tymczasowej, skąd jest JOIN-owany z etapami trasy.
    CREATE TABLE #TempHQ (
        IdPrzesylki         INT,
        IdSortowniDocelowej INT
    );

    DECLARE @SqlHQ NVARCHAR(1000);
    SET @SqlHQ = N'
        INSERT INTO #TempHQ (IdPrzesylki, IdSortowniDocelowej)
        SELECT p.IdPrzesylki, p.IdSortowniDocelowej
        FROM OPENQUERY([SQLSRV-HQ],
            ''SELECT IdPrzesylki, IdSortowniDocelowej
              FROM WarszawaHQ.dbo.Przesylki
              WHERE StatusPrzesylki = ''''DO_DORECZE''''
                AND IdKuriera = ' + CAST(@IdKuriera AS NVARCHAR(10)) + ''')';

    EXEC sp_executesql @SqlHQ;

    -- Łączymy wynik z etapami trasy; paczki bez pasującej strefy trafiają na koniec
    DECLARE @Przesylki TABLE (
        IdPrzesylki          INT,
        KolejnoscRozladunku  INT,  -- Kolejność dostarczenia (1 = pierwsza w trasie)
        KolejnoscZaladunku   INT,  -- Kolejność załadowania (odwrotna LIFO)
        SektorTira           VARCHAR(20)
    );

    INSERT INTO @Przesylki (IdPrzesylki, KolejnoscRozladunku)
    SELECT
        hq.IdPrzesylki,
        ISNULL(et.KolejnoscRozladunku, @LiczbaEtapow + 1)
    FROM #TempHQ hq
    LEFT JOIN EtapyTrasy et
        ON et.IdTrasy    = @IdTrasy
       AND et.IdSortowni = hq.IdSortowniDocelowej;

    DROP TABLE #TempHQ;

    IF NOT EXISTS (SELECT 1 FROM @Przesylki)
    BEGIN
        PRINT 'Brak przesyłek do doręczenia dla kuriera ' + CAST(@IdKuriera AS VARCHAR(10)) + ' dzisiaj.';
        RETURN;
    END;

    -- === KROK 4: Wylicz kolejność załadunku (LIFO) i sektor tira ===
    -- KolejnoscZaladunku = (@LiczbaEtapow + 1) - KolejnoscRozladunku + offset dla paczek w tym etapie
    -- Sektor tira: etapy w drugiej połowie trasy → TYŁ, środek → SRODEK, pierwsza połowa → PRZOD
    ;WITH RankedPaczki AS (
        SELECT
            IdPrzesylki,
            KolejnoscRozladunku,
            -- Wyliczamy odwróconą kolejność (LIFO): ostatni do rozładunku = pierwszy do załadunku
            ROW_NUMBER() OVER (ORDER BY KolejnoscRozladunku DESC) AS KolejnoscZaladunku
        FROM @Przesylki
    )
    UPDATE @Przesylki
    SET
        KolejnoscZaladunku = rp.KolejnoscZaladunku,
        SektorTira = CASE
            -- Pierwsza 1/3 trasy (dostarczana jako ostatnia) → ładowana na końcu → PRZÓD
            WHEN p.KolejnoscRozladunku <= @LiczbaEtapow / 3
                THEN 'PRZOD'
            -- Ostatnia 1/3 trasy (dostarczana jako pierwsza) → ładowana jako pierwsza → TYŁ
            WHEN p.KolejnoscRozladunku > (@LiczbaEtapow * 2) / 3
                THEN 'TYL'
            -- Środkowe etapy → ŚRODEK
            ELSE 'SRODEK'
        END
    FROM @Przesylki p
    JOIN RankedPaczki rp ON p.IdPrzesylki = rp.IdPrzesylki;

    -- === KROK 5: Wyczyść poprzedni manifest i wstaw nowy ===
    DELETE FROM ZaladunekPojazdu
    WHERE IdPrzydzialu = @IdPrzydzialu;

    INSERT INTO ZaladunekPojazdu (IdPrzydzialu, IdPrzesylki, KolejnoscZaladunku, SektorTira)
    SELECT
        @IdPrzydzialu,
        IdPrzesylki,
        KolejnoscZaladunku,
        SektorTira
    FROM @Przesylki
    ORDER BY KolejnoscZaladunku;

    -- === KROK 6: Zwróć gotowy manifest załadunkowy ===
    SELECT
        z.KolejnoscZaladunku                        AS [Lp. załadunku],
        z.IdPrzesylki                               AS [ID Przesyłki],
        z.SektorTira                                AS [Sektor tira],
        et.KolejnoscRozladunku                      AS [Kolejność doręczenia],
        t.NazwaTrasy                                AS [Trasa],
        et.IdSortowni                               AS [Strefa doręczenia]
    FROM ZaladunekPojazdu z
    JOIN PrzydzialyKurierow pk ON z.IdPrzydzialu = pk.IdPrzydzialu
    JOIN Trasy t               ON t.IdTrasy      = pk.IdTrasy
    -- Etap wyznaczony przez kolejność doręczenia wyliczoną wcześniej
    JOIN EtapyTrasy et         ON et.IdTrasy     = pk.IdTrasy
    -- Łączymy z powrotem przez zmienną, żeby odczytać KolejnoscRozladunku
    JOIN @Przesylki p          ON p.IdPrzesylki  = z.IdPrzesylki
                               AND et.KolejnoscRozladunku = p.KolejnoscRozladunku
    WHERE z.IdPrzydzialu = @IdPrzydzialu
    ORDER BY z.KolejnoscZaladunku;

    PRINT 'Manifest załadunkowy dla kuriera ' + CAST(@IdKuriera AS VARCHAR(10)) + ' został wygenerowany pomyślnie.';
END;
GO
