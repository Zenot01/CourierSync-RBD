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

-- Konfiguracja SQL Server Agent Job
USE [msdb];
GO

-- Usunięcie istniejącego Joba
IF EXISTS (SELECT job_id FROM sysjobs WHERE name = N'Replikacja_Cennika_Oracle_Snapshot')
BEGIN
    EXEC dbo.sp_delete_job @job_name = N'Replikacja_Cennika_Oracle_Snapshot';
END
GO

-- Dodanie Joba
EXEC dbo.sp_add_job 
    @job_name = N'Replikacja_Cennika_Oracle_Snapshot', 
    @enabled = 1, 
    @description = N'Pobiera cennik z bazy Oracle raz na dobę i nadpisuje lokalną tabelę Cennik_Replica';
GO

-- Dodanie kroku
EXEC dbo.sp_add_jobstep 
    @job_name = N'Replikacja_Cennika_Oracle_Snapshot', 
    @step_name = N'Uruchomienie procedury synchronizacji', 
    @subsystem = N'TSQL', 
    @command = N'EXEC WarszawaHQ.dbo.usp_SynchronizujCennikOracle;', 
    @database_name = N'WarszawaHQ',
    @retry_attempts = 3, 
    @retry_interval = 10;
GO

-- Harmonogram codzienny (01:00)
EXEC dbo.sp_add_schedule 
    @schedule_name = N'Harmonogram_Codzienny_0100', 
    @freq_type = 4, -- Codziennie
    @freq_interval = 1, 
    @active_start_time = 010000; -- 01:00:00
GO

-- Przypisanie harmonogramu
EXEC dbo.sp_attach_schedule 
    @job_name = N'Replikacja_Cennika_Oracle_Snapshot', 
    @schedule_name = N'Harmonogram_Codzienny_0100';
GO

-- Przypisanie serwera docelowego
EXEC dbo.sp_add_jobserver 
    @job_name = N'Replikacja_Cennika_Oracle_Snapshot', 
    @server_name = @@SERVERNAME;
GO
