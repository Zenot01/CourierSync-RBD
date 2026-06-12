USE WarszawaHQ;
GO

-- Procedury transakcyjne (Warszawa)

-- usp_PotwierdzDoreczenie: Potwierdzenie doręczenia (transakcja rozproszona MS DTC)
CREATE OR ALTER PROCEDURE usp_PotwierdzDoreczenie
    @IdPrzesylki INT,
    @IdKuriera INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON; -- Wymagane dla transakcji rozproszonych

    -- Pobranie danych przesyłki
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
        -- Wycena fallback
        EXEC usp_WycenPrzesylke @IdPrzesylki = @IdPrzesylki;
        SELECT @KwotaBrutto = WyliczonaOplata FROM Przesylki WHERE IdPrzesylki = @IdPrzesylki;
    END

    -- Obliczenie netto/VAT
    DECLARE @KwotaNetto DECIMAL(10,2) = ROUND(@KwotaBrutto / 1.23, 2);
    DECLARE @KwotaVat DECIMAL(10,2) = @KwotaBrutto - @KwotaNetto;
    
    -- Generowanie numeru faktury
    DECLARE @NumerFaktury VARCHAR(50) = 'FV/' + CAST(@IdPrzesylki AS VARCHAR) + '/' + CONVERT(VARCHAR(8), GETDATE(), 112);

    -- Pobranie sortowni kuriera
    DECLARE @IdSortowni INT;
    SELECT TOP 1 @IdSortowni = s.IdSortowni
    FROM Sortownie s
    JOIN Pracownicy p ON s.IdOddzialu = p.IdOddzialu
    WHERE p.IdPracownika = @IdKuriera;

    IF @IdSortowni IS NULL
    BEGIN
        SELECT TOP 1 @IdSortowni = IdSortowni FROM Sortownie;
    END

    -- Start transakcji rozproszonej (MS DTC)
    BEGIN DISTRIBUTED TRANSACTION;

    BEGIN TRY
        -- 1. Status przesyłki w centrali (lokalnie)
        UPDATE Przesylki
        SET StatusPrzesylki = 'Dostarczona'
        WHERE IdPrzesylki = @IdPrzesylki;

        -- 2. Zdarzenie logistyczne w oddziale (Linked Server)
        EXEC [SQLSRV-REG].KrakowHQ.dbo.usp_ZapiszZdarzenieLogistyczne 
            @IdPrzesylki = @IdPrzesylki,
            @KodZdarzenia = 'DORECZONO',
            @IdKuriera = @IdKuriera,
            @Lokalizacja = @IdSortowni;

        -- 3. Wystawienie faktury w Oracle (RPC)
        DECLARE @Sql NVARCHAR(MAX) = N'BEGIN COURIER_ADMIN.usp_WystawFakture(?, ?, ?, ?, ?, ?); END;';
        EXEC (@Sql, @IdKlienta, @NumerFaktury, @KwotaNetto, @KwotaVat, @KwotaBrutto, @IdPrzesylki) AT [ORA-ACCT];

        -- Zatwierdzenie transakcji
        COMMIT TRANSACTION;
        PRINT 'Dostarczenie przesyłki potwierdzone i zafakturowane pomyślnie.';
    END TRY
    BEGIN CATCH
        -- Wycofanie transakcji przy błędzie
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH
END;
GO
