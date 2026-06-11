-- =========================================================================
-- KONFIGURACJA REPLIKACJI - WARSZAWA CENTRALNY WĘZEŁ (SQLSRV-HQ)
-- =========================================================================

USE [master];
GO

-- Włączenie opcji Ad Hoc w celu możliwości użycia OPENROWSET w replikacji migawkowej
EXEC sys.sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sys.sp_configure 'Ad Hoc Distributed Queries', 1;
RECONFIGURE;
GO

-- UWAGA: Standardowa replikacja transakcyjna (SQLSRV-HQ -> SQLSRV-REG) dla tabel Klienci, Zamowienia, Przesylki
-- powinna być konfigurowana graficznie (GUI) w SQL Server Management Studio (SSMS).
-- Kod konfiguracyjny (distributor, publication, subscription) został usunięty, ponieważ 
-- można go w prosty sposób wygenerować za pomocą kreatora SSMS.
-- Dokładną instrukcję krok po kroku znajdziesz w pliku docs/MS_DTC_Replikacja.md.


-- =========================================================================
-- CZĘŚĆ B: SYMULACJA REPLIKACJI MIGAWKOWEJ (ORACLE -> SQLSRV-HQ)
-- Kopiuje cennik z Oracle raz na dobę w celu lokalnej weryfikacji
-- =========================================================================

-- 1. Utworzenie lokalnej tabeli repliki cennika w centrali
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

-- 2. Stworzenie procedury synchronizacji (Snapshot) cennika z Oracle do SQL Server
CREATE OR ALTER PROCEDURE usp_SynchronizujCennikOracle
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        -- Truncate lokalnej kopii
        TRUNCATE TABLE Cennik_Replica;
        
        -- Wstawienie świeżych danych z Oracle za pomocą OPENROWSET
        INSERT INTO Cennik_Replica (id_uslugi, nazwa_uslugi, cena_bazowa, cena_za_kg)
        SELECT 
            CAST(id_uslugi AS INT),
            CAST(nazwa_uslugi AS VARCHAR(100)),
            CAST(cena_bazowa AS DECIMAL(10, 2)),
            CAST(cena_za_kg AS DECIMAL(10, 2))
        FROM OPENROWSET('OraOLEDB.Oracle', 'XE';'COURIER_RO';'ROSecure123!', 'SELECT id_uslugi, nazwa_uslugi, cena_bazowa, cena_za_kg FROM COURIER_ADMIN.Cennik');
        
        PRINT 'Pomyślnie zsynchronizowano cennik z Oracle (Replikacja migawkowa).';
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg NVARCHAR(4000) = 'Błąd replikacji migawkowej cennika: ' + ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END;
GO

-- 3. Konfiguracja cyklicznego SQL Server Agent Joba (uruchamianego raz na dobę)
USE [msdb];
GO

-- Usuwanie istniejącego Joba w celu idempotentności
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

-- Dodanie kroku do Joba
EXEC dbo.sp_add_jobstep 
    @job_name = N'Replikacja_Cennika_Oracle_Snapshot', 
    @step_name = N'Uruchomienie procedury synchronizacji', 
    @subsystem = N'TSQL', 
    @command = N'EXEC WarszawaHQ.dbo.usp_SynchronizujCennikOracle;', 
    @database_name = N'WarszawaHQ',
    @retry_attempts = 3, 
    @retry_interval = 10;
GO

-- Dodanie harmonogramu (codziennie o godzinie 01:00)
EXEC dbo.sp_add_schedule 
    @schedule_name = N'Harmonogram_Codzienny_0100', 
    @freq_type = 4, -- Codziennie
    @freq_interval = 1, 
    @active_start_time = 010000; -- 01:00:00
GO

-- Przypisanie harmonogramu do Joba
EXEC dbo.sp_attach_schedule 
    @job_name = N'Replikacja_Cennika_Oracle_Snapshot', 
    @schedule_name = N'Harmonogram_Codzienny_0100';
GO

-- Przypisanie serwera docelowego (lokalny)
EXEC dbo.sp_add_jobserver 
    @job_name = N'Replikacja_Cennika_Oracle_Snapshot', 
    @server_name = @@SERVERNAME;
GO
