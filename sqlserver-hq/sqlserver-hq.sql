-- Warszawa
CREATE LOGIN CentralAdminLogin WITH PASSWORD = 'HQAdminPassword123!';
CREATE LOGIN AppCentralLogin WITH PASSWORD = 'HQAppPassword123!';

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

-- test polaczenia
EXEC sys.sp_testlinkedserver N'SQLSRV-REG';
GO

EXEC sys.sp_addlinkedserver   
   @server = N'ORA-ACCT',   
   @srvproduct = N'Oracle',   
   @provider = N'OraOLEDB.Oracle',   
   @datasrc = N''; 


EXEC sys.sp_addlinkedsrvlogin   
   @rmtsrvname = N'ORA-ACCT',   
   @useself = N'False',   
   @rmtuser = N'COURIER_RO',          
   @rmtpassword = N'ROSecure123!';  
GO

-- Weryfikacja dostępności połączenia
EXEC sys.sp_testlinkedserver N'ORA-ACCT';
GO

USE WarszawaHQ;

-- Tabela: Oddzialy
CREATE TABLE Oddzialy (
    IdOddzialu INT IDENTITY(1,1) PRIMARY KEY,
    Nazwa VARCHAR(100) NOT NULL,
    Miasto VARCHAR(50) NOT NULL
);

-- Tabela: Pracownicy
CREATE TABLE Pracownicy (
    IdPracownika INT IDENTITY(1,1) PRIMARY KEY,
    Imie VARCHAR(50) NOT NULL,
    Nazwisko VARCHAR(50) NOT NULL,
    Stanowisko VARCHAR(50) NOT NULL,
    IdOddzialu INT FOREIGN KEY REFERENCES Oddzialy(IdOddzialu)
);

-- Tabela: Klienci
CREATE TABLE Klienci (
    IdKlienta INT IDENTITY(1,1) PRIMARY KEY,
    NazwaFirmy_ImieNazwisko VARCHAR(150) NOT NULL,
    NIP VARCHAR(10) NULL,
    Adres VARCHAR(200) NOT NULL,
    Telefon VARCHAR(15) NOT NULL
);

-- Tabela: Zamowienia
CREATE TABLE Zamowienia (
    IdZamowienia INT IDENTITY(1,1) PRIMARY KEY,
    IdKlienta INT FOREIGN KEY REFERENCES Klienci(IdKlienta),
    DataZlozenia DATETIME DEFAULT GETDATE(),
    StatusZamowienia VARCHAR(30) DEFAULT 'PRZYJETE'
);

-- Tabela: Przesylki
CREATE TABLE Przesylki (
    IdPrzesylki INT IDENTITY(1,1) PRIMARY KEY,
    IdZamowienia INT FOREIGN KEY REFERENCES Zamowienia(IdZamowienia),
    IdKlientaNadawcy INT FOREIGN KEY REFERENCES Klienci(IdKlienta),
    WyliczonaOplata DECIMAL(10,2) NULL, -- Uzupełniane przez procedurę usp_WycenPrzesylke
    StatusPrzesylki VARCHAR(30)
);
