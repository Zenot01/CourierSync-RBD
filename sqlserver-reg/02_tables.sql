USE KrakowHQ;
GO

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

-- Tabela: EtapyTrasy
CREATE TABLE EtapyTrasy (
    IdEtapu INT IDENTITY(1,1) PRIMARY KEY,
    IdTrasy INT FOREIGN KEY REFERENCES Trasy(IdTrasy),
    IdSortowni INT NOT NULL, -- Powiązanie z HQ
    KolejnoscRozladunku INT NOT NULL, -- Numer przystanku
    CONSTRAINT UC_TrasaKolejnosc UNIQUE (IdTrasy, KolejnoscRozladunku)
);

-- Tabela: PrzydzialyKurierow
CREATE TABLE PrzydzialyKurierow (
    IdPrzydzialu INT IDENTITY(1,1) PRIMARY KEY,
    IdKuriera INT NOT NULL, -- Powiązanie z HQ
    IdPojazdu INT FOREIGN KEY REFERENCES Pojazdy(IdPojazdu),
    IdTrasy INT FOREIGN KEY REFERENCES Trasy(IdTrasy),
    DataPrzydzialu DATE DEFAULT CAST(GETDATE() AS DATE)
);

-- Tabela: ZaladunekPojazdu
CREATE TABLE ZaladunekPojazdu (
    IdZaladunku INT IDENTITY(1,1) PRIMARY KEY,
    IdPrzydzialu INT FOREIGN KEY REFERENCES PrzydzialyKurierow(IdPrzydzialu),
    IdPrzesylki INT NOT NULL, -- Powiązanie z HQ
    KolejnoscZaladunku INT NOT NULL, -- Kolejność ładowania
    SektorTira VARCHAR(20) NULL -- Sektor
);

-- Tabela: ZdarzeniaLogistyczne
CREATE TABLE ZdarzeniaLogistyczne (
    IdZdarzenia INT IDENTITY(1,1) PRIMARY KEY,
    IdPrzesylki INT NOT NULL, -- Powiązanie z HQ
    KodZdarzenia VARCHAR(20) NOT NULL, -- Kod statusu
    IdKuriera INT NOT NULL,
    IdSortowni INT NOT NULL, -- Powiązanie z HQ
    DataZdarzenia DATETIME DEFAULT GETDATE()
);

-- Indeks unikalny
CREATE UNIQUE INDEX UIDX_Zdarzenia_ZapobieganieDuplikatom 
ON ZdarzeniaLogistyczne (IdPrzesylki, KodZdarzenia, DataZdarzenia);

GO
