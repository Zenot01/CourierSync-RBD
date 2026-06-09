USE WarszawaHQ;
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
            @Lokalizacja = @IdSortowni;

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
