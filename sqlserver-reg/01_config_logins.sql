-- Konfiguracja serwera regionalnego (Kraków)
-- Wymagany kontekst bazy master
USE [master];
GO

-- Reset bazy KrakowHQ
IF EXISTS (SELECT * FROM sys.databases WHERE name = 'KrakowHQ')
BEGIN
    ALTER DATABASE KrakowHQ SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE KrakowHQ;
END
GO

CREATE DATABASE KrakowHQ;
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

-- Tworzenie użytkowników
CREATE USER COURIER_REG_ADMIN FOR LOGIN RegionalAdminLogin;
CREATE USER COURIER_LINKED_HQ FOR LOGIN LinkedServerLogin;
GO

-- Uprawnienia
ALTER ROLE db_owner ADD MEMBER COURIER_REG_ADMIN;
ALTER ROLE db_datawriter ADD MEMBER COURIER_LINKED_HQ;
ALTER ROLE db_datareader ADD MEMBER COURIER_LINKED_HQ;
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

-- RPC dla SQLSRV-HQ
EXEC sys.sp_serveroption @server=N'SQLSRV-HQ', @optname=N'rpc', @optvalue=N'true';
EXEC sys.sp_serveroption @server=N'SQLSRV-HQ', @optname=N'rpc out', @optvalue=N'true';
GO

