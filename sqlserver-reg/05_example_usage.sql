USE KrakowHQ;
GO

-- Przygotowanie danych testowych lokalnych
DECLARE @IdKuriera INT = 1; -- IdKuriera w centrali
DECLARE @IdPojazdu INT;
DECLARE @IdTrasy INT;
DECLARE @IdPrzydzialu INT;

-- 1. Dodanie pojazdu kurierskiego z unikalnym numerem rejestracyjnym
DECLARE @Rejestracja VARCHAR(15) = 'KR-' + CAST(CAST(RAND()*100000 AS INT) AS VARCHAR(10));
INSERT INTO Pojazdy (NrRejestracyjny, Marka, Model)
VALUES (@Rejestracja, 'Renault', 'Master');
SET @IdPojazdu = SCOPE_IDENTITY();

-- 2. Dodanie trasy
INSERT INTO Trasy (NazwaTrasy, OpisStrefy)
VALUES ('Trasa Polnocna - Krakow', 'Obszar Nowa Huta, Pradnik Czerwony');
SET @IdTrasy = SCOPE_IDENTITY();

-- 3. Dodanie etapów trasy (przystanków/sortowni docelowych w kolejności dostaw)
-- Przystanek 1: Sortownia o ID = 1 (Pierwszy w kolejności rozładunku)
INSERT INTO EtapyTrasy (IdTrasy, IdSortowni, KolejnoscRozladunku)
VALUES (@IdTrasy, 1, 1);

-- Przystanek 2: Sortownia o ID = 2
INSERT INTO EtapyTrasy (IdTrasy, IdSortowni, KolejnoscRozladunku)
VALUES (@IdTrasy, 2, 2);

-- Przystanek 3: Sortownia o ID = 3 (Ostatni w kolejności rozładunku)
INSERT INTO EtapyTrasy (IdTrasy, IdSortowni, KolejnoscRozladunku)
VALUES (@IdTrasy, 3, 3);

-- 4. Przydział kuriera do pojazdu i trasy na dzisiejszy dzień
INSERT INTO PrzydzialyKurierow (IdKuriera, IdPojazdu, IdTrasy, DataPrzydzialu)
VALUES (@IdKuriera, @IdPojazdu, @IdTrasy, CAST(GETDATE() AS DATE));
SET @IdPrzydzialu = SCOPE_IDENTITY();


-- Optymalizacja trasy kuriera (Manifest Załadunkowy LIFO)
BEGIN TRY
    -- Wywołanie procedury optymalizacji
    EXEC usp_OptymalizujTrase @IdKuriera = @IdKuriera;

    -- Zawartość wygenerowanego manifestu załadunku
    SELECT IdZaladunku, IdPrzydzialu, IdPrzesylki, KolejnoscZaladunku, SektorTira 
    FROM ZaladunekPojazdu 
    WHERE IdPrzydzialu = @IdPrzydzialu;
END TRY
BEGIN CATCH
    -- Występuje błąd gdy Linked Server SQLSRV-HQ jest nieaktywny
    PRINT 'Uwaga: Optymalizacja trasy kuriera nie powiodla sie (brak polaczenia z HQ). Blad: ' + ERROR_MESSAGE();
END CATCH


-- Rejestrowanie zdarzeń logistycznych dla paczki
DECLARE @IdPrzesylkiTestowej INT = 101;
DECLARE @IdKurieraZdarzenia INT = @IdKuriera;
DECLARE @LokalizacjaZdarzenia INT = 1; -- IdSortowni

-- A. Pierwsza rejestracja zdarzenia (np. załadunek na auto)
EXEC usp_ZapiszZdarzenieLogistyczne 
    @IdPrzesylki = @IdPrzesylkiTestowej, 
    @KodZdarzenia = 'W_TRASIE', 
    @IdKuriera = @IdKurieraZdarzenia, 
    @Lokalizacja = @LokalizacjaZdarzenia;

-- B. Próba ponownej rejestracji tego samego zdarzenia (zabezpieczenie przed duplikatami)
EXEC usp_ZapiszZdarzenieLogistyczne 
    @IdPrzesylki = @IdPrzesylkiTestowej, 
    @KodZdarzenia = 'W_TRASIE', 
    @IdKuriera = @IdKurieraZdarzenia, 
    @Lokalizacja = @LokalizacjaZdarzenia;

-- C. Weryfikacja zapisanych zdarzeń w bazie dla testowanej paczki
SELECT IdZdarzenia, IdPrzesylki, KodZdarzenia, IdKuriera, IdSortowni, DataZdarzenia
FROM ZdarzeniaLogistyczne
WHERE IdPrzesylki = @IdPrzesylkiTestowej;
GO
