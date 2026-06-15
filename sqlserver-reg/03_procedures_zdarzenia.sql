USE KrakowHQ;
GO

-- PROCEDURY SKŁADOWANE (KRAKÓW ODDZIAŁ REGIONALNY)

-- 1. usp_ZapiszZdarzenieLogistyczne
-- Zapisuje zdarzenie logistyczne w lokalnej bazie.
CREATE OR ALTER PROCEDURE usp_ZapiszZdarzenieLogistyczne
    @IdPrzesylki INT,
    @KodZdarzenia VARCHAR(20),
    @IdKuriera INT,
    @Lokalizacja INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Sprawdzenie, czy takie same zdarzenie już zostało zapisane w bieżącym dniu
    IF NOT EXISTS (
        SELECT 1 
        FROM ZdarzeniaLogistyczne 
        WHERE IdPrzesylki = @IdPrzesylki 
          AND KodZdarzenia = @KodZdarzenia 
          AND CAST(DataZdarzenia AS DATE) = CAST(GETDATE() AS DATE)
    )
    BEGIN
        INSERT INTO ZdarzeniaLogistyczne (IdPrzesylki, KodZdarzenia, IdKuriera, IdSortowni, DataZdarzenia)
        VALUES (@IdPrzesylki, @KodZdarzenia, @IdKuriera, @Lokalizacja, GETDATE());
        
        PRINT 'Zapisano zdarzenie logistyczne: ' + @KodZdarzenia;
    END
    ELSE
    BEGIN
        PRINT 'Zdarzenie logistyczne: ' + @KodZdarzenia + ' już istnieje dla tej przesyłki dzisiaj. Pominięto.';
    END
END;
GO
