-- Włączenie opcji Ad Hoc (OPENROWSET)
USE [master];
GO

EXEC sys.sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sys.sp_configure 'Ad Hoc Distributed Queries', 1;
RECONFIGURE;

-- Reset bazy danych WarszawaHQ (tylko jeśli nie jest używana w replikacji)
IF EXISTS (SELECT * FROM sys.databases WHERE name = 'WarszawaHQ')
BEGIN
    BEGIN TRY
        -- Jeśli baza istnieje, sprawdzamy czy ma aktywne publikacje replikacji
        IF OBJECT_ID('WarszawaHQ.sys.publications') IS NULL 
           OR NOT EXISTS (SELECT 1 FROM WarszawaHQ.sys.publications)
        BEGIN
            ALTER DATABASE WarszawaHQ SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
            DROP DATABASE WarszawaHQ;
            EXEC ('CREATE DATABASE WarszawaHQ');
            PRINT 'Baza WarszawaHQ została zresetowana.';
        END
        ELSE
        BEGIN
            PRINT 'Baza WarszawaHQ istnieje i zawiera publikacje replikacji. Pominięto ponowne tworzenie bazy.';
        END
    END TRY
    BEGIN CATCH
        PRINT 'Nie można zresetować bazy WarszawaHQ (prawdopodobnie jest używana w replikacji). Używam istniejącej bazy.';
    END CATCH
END
ELSE
BEGIN
    CREATE DATABASE WarszawaHQ;
    PRINT 'Baza WarszawaHQ została utworzona.';
END
GO

-- Tworzenie loginów serwera
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

-- Tworzenie użytkowników bazy (tylko jeśli nie istnieją)
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'COURIER_HQ_ADMIN')
BEGIN
    CREATE USER COURIER_HQ_ADMIN FOR LOGIN CentralAdminLogin;
END
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'COURIER_HQ_APP')
BEGIN
    CREATE USER COURIER_HQ_APP FOR LOGIN AppCentralLogin;
END
GO

-- Przypisanie do ról bazodanowych
IF IS_ROLEMEMBER('db_owner', 'COURIER_HQ_ADMIN') = 0
BEGIN
    ALTER ROLE db_owner ADD MEMBER COURIER_HQ_ADMIN;
END
GO

IF IS_ROLEMEMBER('db_datawriter', 'COURIER_HQ_APP') = 0
BEGIN
    ALTER ROLE db_datawriter ADD MEMBER COURIER_HQ_APP;
END
GO

IF IS_ROLEMEMBER('db_datareader', 'COURIER_HQ_APP') = 0
BEGIN
    ALTER ROLE db_datareader ADD MEMBER COURIER_HQ_APP;
END
GO


USE [master];
GO

-- Linked Server: SQLSRV-REG
IF EXISTS (SELECT * FROM sys.servers WHERE name = 'SQLSRV-REG')
BEGIN
    EXEC sys.sp_dropserver @server = 'SQLSRV-REG', @droplogins = 'droplogins';
END
GO

EXEC sys.sp_addlinkedserver   
   @server = N'SQLSRV-REG',   
   @srvproduct = N'',
   @provider = N'MSOLEDBSQL',   
   @datasrc = N'localhost\KRAKOW_HQ';
GO


EXEC sys.sp_addlinkedsrvlogin   
   @rmtsrvname = N'SQLSRV-REG',   
   @useself = N'False',
   @rmtuser = N'LinkedServerLogin',
   @rmtpassword = N'REGLinkedPassword123!';
GO

-- RPC dla SQLSRV-REG
EXEC sys.sp_serveroption @server=N'SQLSRV-REG', @optname=N'rpc', @optvalue=N'true';
EXEC sys.sp_serveroption @server=N'SQLSRV-REG', @optname=N'rpc out', @optvalue=N'true';
GO

-- Test połączenia
BEGIN TRY
    EXEC sys.sp_testlinkedserver N'SQLSRV-REG';
    PRINT 'Połączenie z SQLSRV-REG działa poprawnie.';
END TRY
BEGIN CATCH
    PRINT 'OSTRZEŻENIE: Nie można połączyć się z SQLSRV-REG. Serwer/Baza może nie być jeszcze uruchomiona.';
END CATCH
GO

-- Linked Server: ORA-ACCT (Oracle)
IF EXISTS (SELECT * FROM sys.servers WHERE name = 'ORA-ACCT')
BEGIN
    EXEC sys.sp_dropserver @server = 'ORA-ACCT', @droplogins = 'droplogins';
END
GO

EXEC sys.sp_addlinkedserver   
   @server = N'ORA-ACCT',   
   @srvproduct = N'Oracle',   
   @provider = N'OraOLEDB.Oracle',   
   @datasrc = N'(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=localhost)(PORT=1522))(CONNECT_DATA=(SERVER=DEDICATED)(SID=rbd2026)))';
GO

-- Mapowanie loginów na role w Oracle
-- Admin -> COURIER_ADMIN
EXEC sys.sp_addlinkedsrvlogin   
   @rmtsrvname = N'ORA-ACCT',   
   @useself = N'False',
   @locallogin = N'CentralAdminLogin',
   @rmtuser = N'COURIER_ADMIN',          
   @rmtpassword = N'AdminSecure123!';  
GO

-- Aplikacja -> COURIER_APP
EXEC sys.sp_addlinkedsrvlogin   
   @rmtsrvname = N'ORA-ACCT',   
   @useself = N'False',
   @locallogin = N'AppCentralLogin',
   @rmtuser = N'COURIER_APP',          
   @rmtpassword = N'AppSecure123!';  
GO

-- Domyślne -> COURIER_RO
EXEC sys.sp_addlinkedsrvlogin   
   @rmtsrvname = N'ORA-ACCT',   
   @useself = N'False',
   @locallogin = NULL,   
   @rmtuser = N'COURIER_RO',          
   @rmtpassword = N'ROSecure123!';  
GO

-- RPC dla ORA-ACCT
EXEC sys.sp_serveroption @server=N'ORA-ACCT', @optname=N'rpc', @optvalue=N'true';
EXEC sys.sp_serveroption @server=N'ORA-ACCT', @optname=N'rpc out', @optvalue=N'true';
GO

-- Test połączenia
BEGIN TRY
    EXEC sys.sp_testlinkedserver N'ORA-ACCT';
    PRINT 'Połączenie z ORA-ACCT działa poprawnie.';
END TRY
BEGIN CATCH
    PRINT 'OSTRZEŻENIE: Nie można połączyć się z ORA-ACCT. Serwer/Baza Oracle może nie być jeszcze uruchomiona.';
END CATCH
GO

-- Linked Server: ACC-LOCAL (Access)
IF EXISTS (SELECT * FROM sys.servers WHERE name = 'ACC-LOCAL')
BEGIN
    EXEC sys.sp_dropserver @server = 'ACC-LOCAL', @droplogins = 'droplogins';
END
GO

-- MS Access (ACC-LOCAL)
EXEC sys.sp_addlinkedserver   
   @server = N'ACC-LOCAL',   
   @srvproduct = N'Access',   
   @provider = N'Microsoft.ACE.OLEDB.12.0',   
   @datasrc = N'C:\Users\WBK\Documents\Projekt\smss_oracl\CourierSync-RBD\access\LocalNadania.accdb';
GO

-- Linked Server: XLS-RAPORTY (Excel)
IF EXISTS (SELECT * FROM sys.servers WHERE name = 'XLS-RAPORTY')
BEGIN
    EXEC sys.sp_dropserver @server = 'XLS-RAPORTY', @droplogins = 'droplogins';
END
GO

-- MS Excel (XLS-RAPORTY)
EXEC sys.sp_addlinkedserver   
   @server = N'XLS-RAPORTY',   
   @srvproduct = N'Excel',   
   @provider = N'Microsoft.ACE.OLEDB.12.0',   
   @datasrc = N'C:\Users\WBK\Documents\Projekt\smss_oracl\CourierSync-RBD\excel\MonthlyReport.xlsx',
   @provstr = N'Excel 12.0 XML;HDR=YES';
GO


