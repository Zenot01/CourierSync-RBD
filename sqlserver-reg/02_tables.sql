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

-- Tabela: EtapyTrasy (kolejność przystanków na trasie)
CREATE TABLE EtapyTrasy (
    IdEtapu INT IDENTITY(1,1) PRIMARY KEY,
    IdTrasy INT FOREIGN KEY REFERENCES Trasy(IdTrasy),
    IdSortowni INT NOT NULL, -- Logiczne powiązanie z HQ_Sortownie
    KolejnoscRozladunku INT NOT NULL, -- Kolejny numer przystanku na trasie (np. 1, 2, 3)
    CONSTRAINT UC_TrasaKolejnosc UNIQUE (IdTrasy, KolejnoscRozladunku)
);

-- Tabela: PrzydzialyKurierow
CREATE TABLE PrzydzialyKurierow (
    IdPrzydzialu INT IDENTITY(1,1) PRIMARY KEY,
    IdKuriera INT NOT NULL, -- IdPracownika pobierane logicznie z HQ przez replikację/widok
    IdPojazdu INT FOREIGN KEY REFERENCES Pojazdy(IdPojazdu),
    IdTrasy INT FOREIGN KEY REFERENCES Trasy(IdTrasy),
    DataPrzydzialu DATE DEFAULT CAST(GETDATE() AS DATE)
);

-- Tabela: ZaladunekPojazdu (manifest załadunkowy LIFO)
CREATE TABLE ZaladunekPojazdu (
    IdZaladunku INT IDENTITY(1,1) PRIMARY KEY,
    IdPrzydzialu INT FOREIGN KEY REFERENCES PrzydzialyKurierow(IdPrzydzialu),
    IdPrzesylki INT NOT NULL, -- Logiczne powiązanie z tabelą Przesylki w HQ
    KolejnoscZaladunku INT NOT NULL, -- Wyliczona kolejność ładowania paczki
    SektorTira VARCHAR(20) NULL -- np. 'PRZOD', 'SRODEK', 'TYL'
);

-- Tabela: ZdarzeniaLogistyczne
CREATE TABLE ZdarzeniaLogistyczne (
    IdZdarzenia INT IDENTITY(1,1) PRIMARY KEY,
    IdPrzesylki INT NOT NULL, -- Logiczne powiązanie z tabelą Przesylki w HQ
    KodZdarzenia VARCHAR(20) NOT NULL, -- np. 'DORECZONO', 'W_TRASIE'
    IdKuriera INT NOT NULL,
    IdSortowni INT NOT NULL, -- Logiczne powiązanie z tabelą Sortownie w HQ
    DataZdarzenia DATETIME DEFAULT GETDATE()
);

-- Unikalny indeks zapobiegający duplikatom
CREATE UNIQUE INDEX UIDX_Zdarzenia_ZapobieganieDuplikatom 
ON ZdarzeniaLogistyczne (IdPrzesylki, KodZdarzenia, DataZdarzenia);

GO
