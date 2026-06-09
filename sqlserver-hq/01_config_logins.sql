-- Włączenie opcji Ad Hoc w celu możliwości użycia OPENROWSET
EXEC sys.sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sys.sp_configure 'Ad Hoc Distributed Queries', 1;
RECONFIGURE;
GO

-- Warszawa
CREATE LOGIN CentralAdminLogin WITH PASSWORD = 'HQAdminPassword123!', DEFAULT_DATABASE = WarszawaHQ;
CREATE LOGIN AppCentralLogin WITH PASSWORD = 'HQAppPassword123!', DEFAULT_DATABASE = WarszawaHQ;
GO

USE WarszawaHQ;

CREATE USER COURIER_HQ_ADMIN FOR LOGIN CentralAdminLogin;
CREATE USER COURIER_HQ_APP FOR LOGIN AppCentralLogin;

-- Nadanie uprawnień administracyjnych/aplikacyjnych w bazie
ALTER ROLE db_owner ADD MEMBER COURIER_HQ_ADMIN;
ALTER ROLE db_datawriter ADD MEMBER COURIER_HQ_APP;
ALTER ROLE db_datareader ADD MEMBER COURIER_HQ_APP;

USE [master];
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

-- test polaczenia
EXEC sys.sp_testlinkedserver N'SQLSRV-REG';
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

-- Weryfikacja dostępności połączenia
EXEC sys.sp_testlinkedserver N'ORA-ACCT';
GO

-- Dodanie serwera połączonego MS Access (ACC-LOCAL)
EXEC sys.sp_addlinkedserver   
   @server = N'ACC-LOCAL',   
   @srvproduct = N'Access',   
   @provider = N'Microsoft.ACE.OLEDB.12.0',   
   @datasrc = N'C:\CourierSync\Database\LocalNadania.accdb';
GO

-- Dodanie serwera połączonego MS Excel (XLS-RAPORTY)
EXEC sys.sp_addlinkedserver   
   @server = N'XLS-RAPORTY',   
   @srvproduct = N'Excel',   
   @provider = N'Microsoft.ACE.OLEDB.12.0',   
   @datasrc = N'C:\CourierSync\Reports\MonthlyReport.xlsx',
   @provstr = N'Excel 12.0 XML;HDR=YES';
GO
