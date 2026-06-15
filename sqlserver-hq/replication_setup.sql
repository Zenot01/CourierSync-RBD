-- Replikacja (Warszawa)

USE [master];
GO

-- Opcje Ad Hoc dla replikacji
EXEC sys.sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sys.sp_configure 'Ad Hoc Distributed Queries', 1;
RECONFIGURE;
GO

-- Instrukcja replikacji transakcyjnej w docs/MS_DTC_Replikacja.md.


-- Symulacja replikacji migawkowej (Oracle -> SQLSRV-HQ)
USE WarszawaHQ;
GO

-- Tabela repliki cennika
IF OBJECT_ID('dbo.Cennik_Replica', 'U') IS NULL
BEGIN
    CREATE TABLE Cennik_Replica (
        id_uslugi INT PRIMARY KEY,
        nazwa_uslugi VARCHAR(100) NOT NULL,
        cena_bazowa DECIMAL(10, 2) NOT NULL,
        cena_za_kg DECIMAL(10, 2) NULL,
        OstatniaAktualizacja DATETIME DEFAULT GETDATE()
    );
END
GO

-- Procedura synchronizacji cennika
CREATE OR ALTER PROCEDURE usp_SynchronizujCennikOracle
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        -- Truncate kopii
        TRUNCATE TABLE Cennik_Replica;
        
        -- Import z Oracle (OPENROWSET)
        INSERT INTO Cennik_Replica (id_uslugi, nazwa_uslugi, cena_bazowa, cena_za_kg)
        SELECT 
            CAST(id_uslugi AS INT),
            CAST(nazwa_uslugi AS VARCHAR(100)),
            CAST(cena_bazowa AS DECIMAL(10, 2)),
            CAST(cena_za_kg AS DECIMAL(10, 2))
        FROM OPENROWSET(
            'OraOLEDB.Oracle', 
            '(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=localhost)(PORT=1522))(CONNECT_DATA=(SERVER=DEDICATED)(SID=rbd2026)))';'COURIER_RO';'ROSecure123!', 
            'SELECT id_uslugi, nazwa_uslugi, cena_bazowa, cena_za_kg FROM COURIER_ADMIN.Cennik'
        );

        PRINT 'Pomyślnie zsynchronizowano cennik z Oracle (Replikacja migawkowa).';
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg NVARCHAR(4000) = 'Błąd replikacji migawkowej cennika: ' + ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END;
GO
