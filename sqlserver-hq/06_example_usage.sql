USE WarszawaHQ;
GO

-- Przygotowanie danych testowych
DECLARE @IdOddzialu INT;
DECLARE @IdSortowni INT;
DECLARE @IdKuriera INT;
DECLARE @IdKlientaNadawcy INT;
DECLARE @IdKlientaOdbiorcy INT;
DECLARE @IdZamowienia INT;
DECLARE @IdPrzesylki INT;

-- 1. Oddział i Sortownia (Sprawdzamy czy istnieją, by zapobiec błędom UNIQUE KEY)
SELECT @IdOddzialu = IdOddzialu FROM Oddzialy WHERE Nazwa = 'Oddzial Krakow';
IF @IdOddzialu IS NULL
BEGIN
    INSERT INTO Oddzialy (Nazwa, Miasto) VALUES ('Oddzial Krakow', 'Krakow');
    SET @IdOddzialu = SCOPE_IDENTITY();
END

SELECT @IdSortowni = IdSortowni FROM Sortownie WHERE KodSortowni = 'KRK-N01';
IF @IdSortowni IS NULL
BEGIN
    INSERT INTO Sortownie (NazwaSortowni, KodSortowni, IdOddzialu)
    VALUES ('Sortownia Krakow Polnoc', 'KRK-N01', @IdOddzialu);
    SET @IdSortowni = SCOPE_IDENTITY();
END

-- 2. Pracownik (Kurier) przypisany do oddziału
SELECT @IdKuriera = IdPracownika FROM Pracownicy WHERE Imie = 'Jan' AND Nazwisko = 'Kowalski' AND Stanowisko = 'KURIER';
IF @IdKuriera IS NULL
BEGIN
    INSERT INTO Pracownicy (Imie, Nazwisko, Stanowisko, IdOddzialu)
    VALUES ('Jan', 'Kowalski', 'KURIER', @IdOddzialu);
    SET @IdKuriera = SCOPE_IDENTITY();
END

-- 3. Klienci (Nadawca i Odbiorca)
SELECT @IdKlientaNadawcy = IdKlienta FROM Klienci WHERE NIP = '1234567890';
IF @IdKlientaNadawcy IS NULL
BEGIN
    INSERT INTO Klienci (NazwaFirmy_ImieNazwisko, NIP, Adres, Telefon)
    VALUES ('Firma Testowa Sp. z o.o.', '1234567890', 'ul. Przemyslowa 5, Warszawa', '123-456-789');
    SET @IdKlientaNadawcy = SCOPE_IDENTITY();
END

SELECT @IdKlientaOdbiorcy = IdKlienta FROM Klienci WHERE NazwaFirmy_ImieNazwisko = 'Anna Nowak' AND Adres = 'ul. Krakowska 12, Krakow';
IF @IdKlientaOdbiorcy IS NULL
BEGIN
    INSERT INTO Klienci (NazwaFirmy_ImieNazwisko, NIP, Adres, Telefon)
    VALUES ('Anna Nowak', NULL, 'ul. Krakowska 12, Krakow', '987-654-321');
    SET @IdKlientaOdbiorcy = SCOPE_IDENTITY();
END

-- 4. Zamówienie
INSERT INTO Zamowienia (IdKlienta, DataZlozenia, StatusZamowienia)
VALUES (@IdKlientaNadawcy, GETDATE(), 'PRZYJETE');
SET @IdZamowienia = SCOPE_IDENTITY();

-- 5. Przesyłka oczekująca na wycenę i przydział
INSERT INTO Przesylki (IdZamowienia, IdKlientaNadawcy, IdKlientaOdbiorcy, TypPrzesylki, Waga, StatusPrzesylki, IdSortowniDocelowej, IdKuriera)
VALUES (@IdZamowienia, @IdKlientaNadawcy, @IdKlientaOdbiorcy, 'EXPRESS', 12.50, 'DO_DORECZENIA', @IdSortowni, @IdKuriera);
SET @IdPrzesylki = SCOPE_IDENTITY();


-- Replika cennika z bazy Oracle
-- Zapewnienie, że w tabeli repliki istnieje przynajmniej domyślna pozycja
IF NOT EXISTS (SELECT 1 FROM Cennik_Replica WHERE nazwa_uslugi = 'EXPRESS')
BEGIN
    INSERT INTO Cennik_Replica (id_uslugi, nazwa_uslugi, cena_bazowa, cena_za_kg, OstatniaAktualizacja)
    VALUES (99, 'EXPRESS', 25.00, 3.50, GETDATE());
END

-- Próba uruchomienia rzeczywistej synchronizacji z Oracle przez Linked Server
-- Używamy dynamicznego SQL, aby zapobiec błędom kompilacji skryptu przy braku połączenia
BEGIN TRY
    EXEC sp_executesql N'EXEC usp_SynchronizujCennikOracle;';
END TRY
BEGIN CATCH
    -- W przypadku braku połączenia z bazą Oracle użyte zostaną dane lokalne
    PRINT 'Uwaga: Replikacja cennika nie powiodla sie, uzyto danych lokalnych.';
END CATCH


-- Wycena przesyłki
-- Przed wyceną:
SELECT IdPrzesylki, TypPrzesylki, Waga, WyliczonaOplata 
FROM Przesylki 
WHERE IdPrzesylki = @IdPrzesylki;

-- Wywołanie procedury wyceny
BEGIN TRY
    EXEC usp_WycenPrzesylke @IdPrzesylki = @IdPrzesylki;
END TRY
BEGIN CATCH
    PRINT 'Uwaga: Nie udalo sie wycenic przesylki (brak procedury usp_WycenPrzesylke).';
END CATCH

-- Po wycenie:
SELECT IdPrzesylki, TypPrzesylki, Waga, WyliczonaOplata 
FROM Przesylki 
WHERE IdPrzesylki = @IdPrzesylki;


-- Import zamówień z MS Access (ACC-LOCAL)
-- Używamy dynamicznego SQL, aby zapobiec błędom kompilacji skryptu przy braku Linked Servera
BEGIN TRY
    EXEC sp_executesql N'EXEC usp_OdswiezRaportXLS @DataGraniczna = ''2026-01-01''';
END TRY
BEGIN CATCH
    PRINT 'Uwaga: Nie udalo sie zaimportowac danych z MS Access. Blad: ' + ERROR_MESSAGE();
END CATCH


-- Potwierdzenie doręczenia przesyłki (MS DTC - transakcja rozproszona)
-- Używamy dynamicznego SQL z przekazaniem parametrów, aby zapobiec błędom kompilacji
BEGIN TRY
    EXEC sp_executesql 
        N'EXEC usp_PotwierdzDoreczenie @IdPrzesylki = @IdPrzesylki, @IdKuriera = @IdKuriera',
        N'@IdPrzesylki INT, @IdKuriera INT',
        @IdPrzesylki = @IdPrzesylki,
        @IdKuriera = @IdKuriera;
END TRY
BEGIN CATCH
    PRINT 'Uwaga: Blad podczas wywolania transakcji rozproszonej usp_PotwierdzDoreczenie. Blad: ' + ERROR_MESSAGE();
END CATCH


-- Raporty i konsolidacja danych
-- Podgląd widoku konsolidacyjnego
-- Używamy dynamicznego SQL, aby zapobiec przerwaniu skryptu z powodu braku sterownika OLE DB Microsoft.ACE.OLEDB.12.0
BEGIN TRY
    EXEC sp_executesql N'SELECT TOP 5 * FROM vw_KonsolidacjaRaportu;';
END TRY
BEGIN CATCH
    PRINT 'Uwaga: Nie udalo sie odczytac widoku vw_KonsolidacjaRaportu. Blad: ' + ERROR_MESSAGE();
END CATCH

-- Wywołanie procedury raportującej za czerwiec 2026
-- Używamy dynamicznego SQL, aby zapobiec przerwaniu skryptu z powodu braku sterowników
BEGIN TRY
    EXEC sp_executesql N'EXEC usp_GenerujRaportKonsolidacyjny @DataOd = ''2026-06-01'', @DataDo = ''2026-06-30''';
END TRY
BEGIN CATCH
    PRINT 'Uwaga: Nie udalo sie wygenerowac raportu konsolidacyjnego. Blad: ' + ERROR_MESSAGE();
END CATCH
GO
