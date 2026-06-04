-- Kraków
CREATE LOGIN RegionalAdminLogin WITH PASSWORD = 'REGAdminPassword123!';
CREATE LOGIN LinkedServerLogin WITH PASSWORD = 'REGLinkedPassword123!'; 

USE KrakowHQ;

CREATE USER COURIER_REG_ADMIN FOR LOGIN RegionalAdminLogin;
CREATE USER COURIER_LINKED_HQ FOR LOGIN LinkedServerLogin;

ALTER ROLE db_owner ADD MEMBER COURIER_REG_ADMIN;
ALTER ROLE db_datawriter ADD MEMBER COURIER_LINKED_HQ;
ALTER ROLE db_datareader ADD MEMBER COURIER_LINKED_HQ;

-- Tabela: Pojazdy
CREATE TABLE Pojazdy (
    IdPojazdu INT IDENTITY(1,1) PRIMARY KEY,
    NrRejestracyjny VARCHAR(15) NOT NULL UNIQUE,
    Marka VARCHAR(50),
    Model VARCHAR(50)
);

-- Tabela: Trasy
CREATE TABLE Trasy (
    IdTrasy INT IDENTITY(1,1) PRIMARY KEY,
    NazwaTrasy VARCHAR(100) NOT NULL,
    OpisStrefy VARCHAR(250)
);

-- Tabela: PrzydzialyKurierow
CREATE TABLE PrzydzialyKurierow (
    IdPrzydzialu INT IDENTITY(1,1) PRIMARY KEY,
    IdKuriera INT NOT NULL, -- IdPracownika pobierane logicznie z HQ przez replikację/widok
    IdPojazdu INT FOREIGN KEY REFERENCES Pojazdy(IdPojazdu),
    IdTrasy INT FOREIGN KEY REFERENCES Trasy(IdTrasy),
    DataPrzydzialu DATE DEFAULT CAST(GETDATE() AS DATE)
);

-- Tabela: ZdarzeniaLogistyczne
CREATE TABLE ZdarzeniaLogistyczne (
    IdZdarzenia INT IDENTITY(1,1) PRIMARY KEY,
    IdPrzesylki INT NOT NULL, -- Logiczne powiązanie z tabelą Przesylki w HQ
    KodZdarzenia VARCHAR(20) NOT NULL, -- np. 'DORECZONO', 'W_TRASIE'
    IdKuriera INT NOT NULL,
    Lokalizacja VARCHAR(100) NOT NULL,
    DataZdarzenia DATETIME DEFAULT GETDATE()
);

-- Unikalny indeks zapobiegający duplikatom
CREATE UNIQUE INDEX UIDX_Zdarzenia_ZapobieganieDuplikatom 
ON ZdarzeniaLogistyczne (IdPrzesylki, KodZdarzenia, DataZdarzenia);