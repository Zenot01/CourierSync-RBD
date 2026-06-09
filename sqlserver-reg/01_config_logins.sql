-- Kraków
-- Loginy muszą być tworzone w kontekście bazy master
USE [master];
GO

CREATE LOGIN RegionalAdminLogin WITH PASSWORD = 'REGAdminPassword123!', DEFAULT_DATABASE = KrakowHQ;
CREATE LOGIN LinkedServerLogin WITH PASSWORD = 'REGLinkedPassword123!', DEFAULT_DATABASE = KrakowHQ;
GO

USE KrakowHQ;

CREATE USER COURIER_REG_ADMIN FOR LOGIN RegionalAdminLogin;
CREATE USER COURIER_LINKED_HQ FOR LOGIN LinkedServerLogin;

ALTER ROLE db_owner ADD MEMBER COURIER_REG_ADMIN;
ALTER ROLE db_datawriter ADD MEMBER COURIER_LINKED_HQ;
ALTER ROLE db_datareader ADD MEMBER COURIER_LINKED_HQ;

-- Konfiguracja Linked Server do Centrali (HQ)
EXEC sys.sp_addlinkedserver   
   @server = N'SQLSRV-HQ',   
   @srvproduct = N'SQL Server',
   @provider = N'MSOLEDBSQL',   
   @datasrc = N'WARSZAWA_HQ';
GO

-- Logowanie do HQ używając konta integracyjnego
EXEC sys.sp_addlinkedsrvlogin   
   @rmtsrvname = N'SQLSRV-HQ',   
   @useself = N'False',
   @locallogin = NULL,
   @rmtuser = N'AppCentralLogin',
   @rmtpassword = N'HQAppPassword123!';
GO

-- Włączenie RPC
EXEC sys.sp_serveroption @server=N'SQLSRV-HQ', @optname=N'rpc', @optvalue=N'true';
EXEC sys.sp_serveroption @server=N'SQLSRV-HQ', @optname=N'rpc out', @optvalue=N'true';
GO
