USE WarszawaHQ;
GO

-- =========================================================================
-- PROCEDURY SKŁADOWANE (WARSZAWA CENTRALNY WĘZEŁ) - ETAP 1
-- =========================================================================

-- =========================================================================
-- 2. usp_WycenPrzesylke
-- Pobiera cennik z serwera Oracle przy użyciu OPENROWSET,
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

    -- Pobranie cennika z lokalnej tabeli repliki (Cennik_Replica)
    SELECT TOP 1 
        @CenaBazowa = cena_bazowa,
        @CenaZaKg = ISNULL(cena_za_kg, 0)
    FROM Cennik_Replica
    WHERE UPPER(nazwa_uslugi) = UPPER(@TypPrzesylki);

    -- Obsługa przypadku braku dopasowania - pobranie ceny standardowej
    IF @CenaBazowa IS NULL
    BEGIN
        SELECT TOP 1 
            @CenaBazowa = cena_bazowa,
            @CenaZaKg = ISNULL(cena_za_kg, 0)
        FROM Cennik_Replica
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
