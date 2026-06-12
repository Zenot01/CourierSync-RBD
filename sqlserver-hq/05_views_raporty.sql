USE WarszawaHQ;
GO

-- vw_KonsolidacjaRaportu: Integracja danych z centrali, Oracle, Access i Excela.
CREATE OR ALTER VIEW vw_KonsolidacjaRaportu AS
SELECT 
    p.IdPrzesylki,
    p.StatusPrzesylki,
    p.WyliczonaOplata,
    -- Dane z Oracle
    f.numer_faktury AS Oracle_NumerFaktury,
    f.kwota_brutto AS Oracle_KwotaBrutto,
    -- Dane z Access
    a.IdNadania AS Access_IdNadania,
    a.DataNadania AS Access_DataNadania,
    -- Dane z Excela
    e.SumaDostaw AS Excel_SumaDostaw,
    e.Miesiac AS Excel_Miesiac
FROM Przesylki p
LEFT JOIN [ORA-ACCT]..[COURIER_ADMIN].[FAKTURY] f ON p.IdPrzesylki = f.id_przesylki
LEFT JOIN [ACC-LOCAL]...Nadania a ON p.IdKlientaNadawcy = a.IdKlienta
LEFT JOIN [XLS-RAPORTY]...[Sheet1$] e ON e.Miesiac = CONVERT(VARCHAR(7), GETDATE(), 120);
GO

-- usp_GenerujRaportKonsolidacyjny: Raport agregujący dane z centrali, Oracle, Access i Excela.
CREATE OR ALTER PROCEDURE usp_GenerujRaportKonsolidacyjny
    @DataOd DATETIME,
    @DataDo DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        k.IdKlienta,
        k.NazwaFirmy_ImieNazwisko,
        
        -- Dane lokalne
        COUNT(DISTINCT p.IdPrzesylki) AS LiczbaPrzesylekLokalnych,
        
        -- Zdalne z Oracle
        CAST(ISNULL(SUM(f.kwota_brutto), 0) AS DECIMAL(10,2)) AS SumaFakturOracle,
        
        -- Zdalne z Access
        COUNT(DISTINCT a.IdNadania) AS LiczbaNadanAccess,
        
        -- Zdalne z Excel
        CAST(ISNULL(SUM(CAST(e.SumaDostaw AS DECIMAL(10,2))), 0) AS DECIMAL(10,2)) AS SumaDostawExcel
    FROM Klienci k
    LEFT JOIN Przesylki p ON k.IdKlienta = p.IdKlientaNadawcy
    -- Dane zdalne Oracle przez Linked Server
    LEFT JOIN [ORA-ACCT]..[COURIER_ADMIN].[FAKTURY] f 
        ON p.IdPrzesylki = f.id_przesylki 
        AND f.data_wystawienia BETWEEN @DataOd AND @DataDo
    -- Dane zdalne Access przez Linked Server
    LEFT JOIN [ACC-LOCAL]...Nadania a 
        ON k.IdKlienta = a.IdKlienta 
        AND a.DataNadania BETWEEN @DataOd AND @DataDo
    -- Dane zdalne Excel przez Linked Server
    LEFT JOIN [XLS-RAPORTY]...[Sheet1$] e 
        ON e.Miesiac = CONVERT(VARCHAR(7), @DataOd, 120)
    GROUP BY k.IdKlienta, k.NazwaFirmy_ImieNazwisko;
END;
GO
