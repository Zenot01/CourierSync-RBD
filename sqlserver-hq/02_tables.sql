USE WarszawaHQ;
GO

-- Tabela: Oddzialy
CREATE TABLE Oddzialy (
    IdOddzialu INT IDENTITY(1,1) PRIMARY KEY,
    Nazwa VARCHAR(100) NOT NULL,
    Miasto VARCHAR(50) NOT NULL
);

-- Tabela: Sortownie
CREATE TABLE Sortownie (
    IdSortowni INT IDENTITY(1,1) PRIMARY KEY,
    NazwaSortowni VARCHAR(100) NOT NULL,
    KodSortowni VARCHAR(20) NOT NULL UNIQUE,
    IdOddzialu INT FOREIGN KEY REFERENCES Oddzialy(IdOddzialu)
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
    IdKlientaOdbiorcy INT FOREIGN KEY REFERENCES Klienci(IdKlienta),
    TypPrzesylki VARCHAR(30) DEFAULT 'STANDARD',
    Waga DECIMAL(10,2) NULL, -- Waga przesyłki używana do wyceny
    IdPrzesylkiOryginalnej INT FOREIGN KEY REFERENCES Przesylki(IdPrzesylki),
    WyliczonaOplata DECIMAL(10,2) NULL, -- Uzupełniane przez procedurę usp_WycenPrzesylke
    StatusPrzesylki VARCHAR(30),
    IdSortowniDocelowej INT FOREIGN KEY REFERENCES Sortownie(IdSortowni), -- Strefa/sortownia docelowa (wyznacza etap trasy kuriera)
    IdKuriera INT NULL -- Kurier przypisany do doręczenia tej przesyłki
);

GO

-- Indeks wspierający filtrowanie paczek do doręczenia wg kuriera i strefy docelowej
CREATE INDEX IDX_Przesylki_StatusKurier
    ON Przesylki (StatusPrzesylki, IdKuriera, IdSortowniDocelowej);
GO
