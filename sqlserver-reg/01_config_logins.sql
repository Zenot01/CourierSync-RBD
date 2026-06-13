-- Konfiguracja serwera regionalnego (Kraków)
-- Wymagany kontekst bazy master
USE [master];
GO

-- Reset bazy KrakowHQ (tylko jeśli nie jest używana w replikacji jako subskrybent)
IF EXISTS (SELECT * FROM sys.databases WHERE name = 'KrakowHQ')
BEGIN
    BEGIN TRY
        -- Sprawdzamy czy baza jest subskrybentem replikacji
        IF OBJECT_ID('KrakowHQ.sys.subscriptions') IS NULL 
           OR NOT EXISTS (SELECT 1 FROM KrakowHQ.sys.subscriptions)
        BEGIN
            ALTER DATABASE KrakowHQ SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
            DROP DATABASE KrakowHQ;
            EXEC ('CREATE DATABASE KrakowHQ');
            PRINT 'Baza KrakowHQ została zresetowana.';
        END
        ELSE
        BEGIN
            PRINT 'Baza KrakowHQ istnieje i jest używana w replikacji. Pominięto ponowne tworzenie bazy.';
        END
    END TRY
    BEGIN CATCH
        PRINT 'Nie można zresetować bazy KrakowHQ (prawdopodobnie jest używana w replikacji). Używam istniejącej bazy.';
    END CATCH
END
ELSE
BEGIN
    CREATE DATABASE KrakowHQ;
    PRINT 'Baza KrakowHQ została utworzona.';
END
GO

-- Tworzenie loginów
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'RegionalAdminLogin')
BEGIN
    CREATE LOGIN RegionalAdminLogin WITH PASSWORD = 'REGAdminPassword123!', DEFAULT_DATABASE = KrakowHQ;
END
GO

IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'LinkedServerLogin')
BEGIN
    CREATE LOGIN LinkedServerLogin WITH PASSWORD = 'REGLinkedPassword123!', DEFAULT_DATABASE = KrakowHQ;
END
GO

USE KrakowHQ;
GO

-- Tworzenie użytkowników (tylko jeśli nie istnieją)
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'COURIER_REG_ADMIN')
BEGIN
    CREATE USER COURIER_REG_ADMIN FOR LOGIN RegionalAdminLogin;
END
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'COURIER_LINKED_HQ')
BEGIN
    CREATE USER COURIER_LINKED_HQ FOR LOGIN LinkedServerLogin;
END
GO

-- Uprawnienia
IF IS_ROLEMEMBER('db_owner', 'COURIER_REG_ADMIN') = 0
BEGIN
    ALTER ROLE db_owner ADD MEMBER COURIER_REG_ADMIN;
END
GO

IF IS_ROLEMEMBER('db_datawriter', 'COURIER_LINKED_HQ') = 0
BEGIN
    ALTER ROLE db_datawriter ADD MEMBER COURIER_LINKED_HQ;
END
GO

IF IS_ROLEMEMBER('db_datareader', 'COURIER_LINKED_HQ') = 0
BEGIN
    ALTER ROLE db_datareader ADD MEMBER COURIER_LINKED_HQ;
END
GO


USE [master];
GO

-- Linked Server: SQLSRV-HQ
IF EXISTS (SELECT * FROM sys.servers WHERE name = 'SQLSRV-HQ')
BEGIN
    EXEC sys.sp_dropserver @server = 'SQLSRV-HQ', @droplogins = 'droplogins';
END
GO

EXEC sys.sp_addlinkedserver   
   @server = N'SQLSRV-HQ',   
   @srvproduct = N'',
   @provider = N'MSOLEDBSQL',   
   @datasrc = N'localhost\WARSZAWA_HQ';
GO


-- Logowanie do HQ
EXEC sys.sp_addlinkedsrvlogin   
   @rmtsrvname = N'SQLSRV-HQ',   
   @useself = N'False',
   @locallogin = NULL,
   @rmtuser = N'AppCentralLogin',
   @rmtpassword = N'HQAppPassword123!';
GO

