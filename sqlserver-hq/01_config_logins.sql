-- Włączenie opcji Ad Hoc w celu możliwości użycia OPENROWSET
USE [master];
GO

EXEC sys.sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sys.sp_configure 'Ad Hoc Distributed Queries', 1;
RECONFIGURE;
GO

-- Usunięcie bazy jeśli istnieje i utworzenie jej na nowo dla czystego startu
IF EXISTS (SELECT * FROM sys.databases WHERE name = 'WarszawaHQ')
BEGIN
    ALTER DATABASE WarszawaHQ SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE WarszawaHQ;
END
GO

CREATE DATABASE WarszawaHQ;
GO

-- Warszawa - Tworzenie loginów jeśli nie istnieją
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'CentralAdminLogin')
BEGIN
    CREATE LOGIN CentralAdminLogin WITH PASSWORD = 'HQAdminPassword123!', DEFAULT_DATABASE = WarszawaHQ;
END
GO

IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'AppCentralLogin')
BEGIN
    CREATE LOGIN AppCentralLogin WITH PASSWORD = 'HQAppPassword123!', DEFAULT_DATABASE = WarszawaHQ;
END
GO

USE WarszawaHQ;
GO

-- Tworzenie użytkowników powiązanych z loginami
CREATE USER COURIER_HQ_ADMIN FOR LOGIN CentralAdminLogin;
CREATE USER COURIER_HQ_APP FOR LOGIN AppCentralLogin;
GO

-- Nadanie uprawnień administracyjnych/aplikacyjnych w bazie
ALTER ROLE db_owner ADD MEMBER COURIER_HQ_ADMIN;
ALTER ROLE db_datawriter ADD MEMBER COURIER_HQ_APP;
ALTER ROLE db_datareader ADD MEMBER COURIER_HQ_APP;
GO

USE [master];
GO

-- 1. SQLSRV-REG
IF EXISTS (SELECT * FROM sys.servers WHERE name = 'SQLSRV-REG')
BEGIN
    EXEC sys.sp_dropserver @server = 'SQLSRV-REG', @droplogins = 'droplogins';
END
GO

EXEC sys.sp_addlinkedserver   
   @server = N'SQLSRV-REG',   
   @srvproduct = N'SQL Server',
   @provider = N'MSOLEDBSQL',   
   @datasrc = N'KRAKOW_HQ';
GO

EXEC sys.sp_addlinkedsrvlogin   
   @rmtsrvname = N'SQLSRV-REG',   
   @useself = N'False',
   @rmtuser = N'LinkedServerLogin',
   @rmtpassword = N'REGLinkedPassword123!';
GO

-- Włączenie RPC i RPC Out dla SQLSRV-REG (wymagane do zdalnych procedur w transakcjach)
EXEC sys.sp_serveroption @server=N'SQLSRV-REG', @optname=N'rpc', @optvalue=N'true';
EXEC sys.sp_serveroption @server=N'SQLSRV-REG', @optname=N'rpc out', @optvalue=N'true';
GO

-- test polaczenia z obsluga bledow
BEGIN TRY
    EXEC sys.sp_testlinkedserver N'SQLSRV-REG';
    PRINT 'Połączenie z SQLSRV-REG działa poprawnie.';
END TRY
BEGIN CATCH
    PRINT 'OSTRZEŻENIE: Nie można połączyć się z SQLSRV-REG. Serwer/Baza może nie być jeszcze uruchomiona.';
END CATCH
GO

-- 2. ORA-ACCT
IF EXISTS (SELECT * FROM sys.servers WHERE name = 'ORA-ACCT')
BEGIN
    EXEC sys.sp_dropserver @server = 'ORA-ACCT', @droplogins = 'droplogins';
END
GO

EXEC sys.sp_addlinkedserver   
   @server = N'ORA-ACCT',   
   @srvproduct = N'Oracle',   
   @provider = N'OraOLEDB.Oracle',   
   @datasrc = N'XE'; 
GO

-- Mapowanie loginów lokalnych na zdalne w Oracle (polityka ról)
-- 1. Mapowanie administratora na konto z pełnymi prawami
EXEC sys.sp_addlinkedsrvlogin   
   @rmtsrvname = N'ORA-ACCT',   
   @useself = N'False',
   @locallogin = N'COURIER_HQ_ADMIN',
   @rmtuser = N'COURIER_ADMIN',          
   @rmtpassword = N'AdminSecure123!';  
GO

-- 2. Mapowanie aplikacji na konto z prawami zapisu/odczytu faktur
EXEC sys.sp_addlinkedsrvlogin   
   @rmtsrvname = N'ORA-ACCT',   
   @useself = N'False',
   @locallogin = N'COURIER_HQ_APP',
   @rmtuser = N'COURIER_APP',          
   @rmtpassword = N'AppSecure123!';  
GO

-- 3. Domyślne mapowanie dla pozostałych użytkowników (tylko do odczytu)
EXEC sys.sp_addlinkedsrvlogin   
   @rmtsrvname = N'ORA-ACCT',   
   @useself = N'False',
   @locallogin = NULL,   
   @rmtuser = N'COURIER_RO',          
   @rmtpassword = N'ROSecure123!';  
GO

-- Włączenie RPC i RPC Out dla ORA-ACCT (wymagane do zdalnego wywoływania PL/SQL)
EXEC sys.sp_serveroption @server=N'ORA-ACCT', @optname=N'rpc', @optvalue=N'true';
EXEC sys.sp_serveroption @server=N'ORA-ACCT', @optname=N'rpc out', @optvalue=N'true';
GO

-- Weryfikacja dostępności połączenia z obsluga bledow
BEGIN TRY
    EXEC sys.sp_testlinkedserver N'ORA-ACCT';
    PRINT 'Połączenie z ORA-ACCT działa poprawnie.';
END TRY
BEGIN CATCH
    PRINT 'OSTRZEŻENIE: Nie można połączyć się z ORA-ACCT. Serwer/Baza Oracle może nie być jeszcze uruchomiona.';
END CATCH
GO

-- 3. ACC-LOCAL
IF EXISTS (SELECT * FROM sys.servers WHERE name = 'ACC-LOCAL')
BEGIN
    EXEC sys.sp_dropserver @server = 'ACC-LOCAL', @droplogins = 'droplogins';
END
GO

-- Dodanie serwera połączonego MS Access (ACC-LOCAL)
EXEC sys.sp_addlinkedserver   
   @server = N'ACC-LOCAL',   
   @srvproduct = N'Access',   
   @provider = N'Microsoft.ACE.OLEDB.12.0',   
   @datasrc = N'C:\CourierSync\Database\LocalNadania.accdb';
GO

-- 4. XLS-RAPORTY
IF EXISTS (SELECT * FROM sys.servers WHERE name = 'XLS-RAPORTY')
BEGIN
    EXEC sys.sp_dropserver @server = 'XLS-RAPORTY', @droplogins = 'droplogins';
END
GO

-- Dodanie serwera połączonego MS Excel (XLS-RAPORTY)
EXEC sys.sp_addlinkedserver   
   @server = N'XLS-RAPORTY',   
   @srvproduct = N'Excel',   
   @provider = N'Microsoft.ACE.OLEDB.12.0',   
   @datasrc = N'C:\CourierSync\Reports\MonthlyReport.xlsx',
   @provstr = N'Excel 12.0 XML;HDR=YES';
GO
