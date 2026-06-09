-- =========================================================================
-- KONFIGURACJA REPLIKACJI - WARSZAWA CENTRALNY WĘZEŁ (SQLSRV-HQ)
-- =========================================================================

USE [master];
GO

-- 1. Włączenie Dystrybutora na serwerze lokalnym
EXEC sp_adddistributor @distributor = @@SERVERNAME, @password = N'DistributorSecurePassword123!';
GO

-- Tworzenie bazy danych dystrybucji
EXEC sp_adddistributiondb 
    @database = N'distribution', 
    @data_folder = N'C:\Program Files\Microsoft SQL Server\MSSQL.Data', 
    @log_folder = N'C:\Program Files\Microsoft SQL Server\MSSQL.Log', 
    @min_distretent = 0, 
    @max_distretent = 72, 
    @history_retent = 48;
GO

-- Konfiguracja wydawcy (Publisher)
EXEC sp_adddistpublisher 
    @publisher = @@SERVERNAME, 
    @distribution_db = N'distribution', 
    @security_mode = 1;
GO

-- 2. Włączenie replikacji dla bazy danych WarszawaHQ
USE [WarszawaHQ];
GO

EXEC sp_replicationdboption 
    @dbname = N'WarszawaHQ', 
    @optname = N'publish', 
    @value = N'true';
GO

-- =========================================================================
-- CZĘŚĆ A: REPLIKACJA TRANSAKCYJNA (SQLSRV-HQ -> SQLSRV-REG)
-- Synchronizuje tabele: Klienci, Zamowienia, Przesylki na bieżąco
-- =========================================================================

-- Dodanie publikacji transakcyjnej
EXEC sp_addpublication 
    @publication = N'Pub_KlienciZamowieniaPrzesylki', 
    @description = N'Replikacja transakcyjna klientów i paczek do oddziału regionalnego', 
    @sync_method = N'concurrent', 
    @retention = 336, 
    @allow_push = N'true', 
    @allow_pull = N'false', 
    @allow_anonymous = N'false', 
    @enabled_for_internet = N'false', 
    @snapshot_in_defaultfolder = N'true', 
    @compress_snapshot = N'false', 
    @ftp_address = NULL, 
    @ftp_port = 21, 
    @ftp_subdirectory = NULL, 
    @ftp_login = N'anonymous', 
    @ftp_password = NULL, 
    @invalidate_gi = 1, 
    @status = N'active';
GO

-- Konfiguracja agenta snapshot dla publikacji
EXEC sp_addpublication_snapshot 
    @publication = N'Pub_KlienciZamowieniaPrzesylki', 
    @frequency_type = 1, 
    @frequency_interval = 1, 
    @frequency_relative_interval = 1, 
    @frequency_recurrence_factor = 0, 
    @frequency_subday = 1, 
    @frequency_subday_interval = 0, 
    @active_start_time_of_day = 0, 
    @active_end_time_of_day = 235959, 
    @active_start_date = 0, 
    @active_end_date = 99991231, 
    @snapshot_job_owner = NULL;
GO

-- Dodanie artykułów (tabel) do publikacji
-- Artykuł 1: Klienci
EXEC sp_addarticle 
    @publication = N'Pub_KlienciZamowieniaPrzesylki', 
    @article = N'Klienci', 
    @source_owner = N'dbo', 
    @source_object = N'Klienci', 
    @type = N'logbased', 
    @description = N'Tabela Klienci', 
    @creation_script = NULL, 
    @pre_creation_cmd = N'drop', 
    @schema_option = 0x000000000803509F, 
    @destination_table = N'Klienci', 
    @destination_owner = N'dbo', 
    @status = 24;
GO

-- Artykuł 2: Zamowienia
EXEC sp_addarticle 
    @publication = N'Pub_KlienciZamowieniaPrzesylki', 
    @article = N'Zamowienia', 
    @source_owner = N'dbo', 
    @source_object = N'Zamowienia', 
    @type = N'logbased', 
    @description = N'Tabela Zamowienia', 
    @creation_script = NULL, 
    @pre_creation_cmd = N'drop', 
    @schema_option = 0x000000000803509F, 
    @destination_table = N'Zamowienia', 
    @destination_owner = N'dbo', 
    @status = 24;
GO

-- Artykuł 3: Przesylki
EXEC sp_addarticle 
    @publication = N'Pub_KlienciZamowieniaPrzesylki', 
    @article = N'Przesylki', 
    @source_owner = N'dbo', 
    @source_object = N'Przesylki', 
    @type = N'logbased', 
    @description = N'Tabela Przesylki', 
    @creation_script = NULL, 
    @pre_creation_cmd = N'drop', 
    @schema_option = 0x000000000803509F, 
    @destination_table = N'Przesylki', 
    @destination_owner = N'dbo', 
    @status = 24;
GO

-- Dodanie subskrypcji typu Push (dla SQLSRV-REG / KrakowHQ)
EXEC sp_addsubscription 
    @publication = N'Pub_KlienciZamowieniaPrzesylki', 
    @subscriber = N'SQLSRV-REG', 
    @destination_db = N'KrakowHQ', 
    @subscription_type = N'Push', 
    @sync_type = N'automatic', 
    @article = N'all', 
    @update_mode = N'read only', 
    @subscriber_type = 0;
GO

-- Konfiguracja agenta dystrybucji na serwerze regionalnym
EXEC sp_addpushsubscription_agent 
    @publication = N'Pub_KlienciZamowieniaPrzesylki', 
    @subscriber = N'SQLSRV-REG', 
    @subscriber_db = N'KrakowHQ', 
    @subscriber_security_mode = 1, -- Zintegrowane uwierzytelnianie
    @frequency_type = 64, -- Praca ciągła
    @frequency_interval = 0, 
    @frequency_relative_interval = 0, 
    @frequency_recurrence_factor = 0, 
    @frequency_subday = 0, 
    @frequency_subday_interval = 0, 
    @active_start_time_of_day = 0, 
    @active_end_time_of_day = 235959, 
    @active_start_date = 0, 
    @active_end_date = 99991231;
GO


-- =========================================================================
-- CZĘŚĆ B: SYMULACJA REPLIKACJI MIGAWKOWEJ (ORACLE -> SQLSRV-HQ)
-- Kopiuje cennik z Oracle raz na dobę w celu lokalnej weryfikacji
-- =========================================================================

-- 1. Utworzenie lokalnej tabeli repliki cennika w centrali
CREATE TABLE Cennik_Replica (
    id_uslugi INT PRIMARY KEY,
    nazwa_uslugi VARCHAR(100) NOT NULL,
    cena_bazowa DECIMAL(10, 2) NOT NULL,
    cena_za_kg DECIMAL(10, 2) NULL,
    OstatniaAktualizacja DATETIME DEFAULT GETDATE()
);
GO

-- 2. Stworzenie procedury synchronizacji (Snapshot) cennika z Oracle do SQL Server
CREATE PROCEDURE usp_SynchronizujCennikOracle
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
        FROM OPENROWSET('OraOLEDB.Oracle', 'XE';'COURIER_RO';'ROSecure123!', 'SELECT id_uslugi, nazwa_uslugi, cena_bazowa, cena_za_kg FROM Cennik');
        
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
