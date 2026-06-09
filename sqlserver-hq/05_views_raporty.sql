USE WarszawaHQ;
GO

-- =========================================================================
-- WIDOKI ROZPROSZONE (WIELODOSTĘP DO RÓŻNYCH ŹRÓDEŁ DANYCH - ORACLE, ACCESS, EXCEL)
-- =========================================================================
-- Widok integruje w jednym miejscu dane z centrali, faktury z Oracle,
-- lokalne nadania z bazy Access oraz raporty miesięczne z Excela.
-- =========================================================================
CREATE OR ALTER VIEW vw_KonsolidacjaRaportu AS
SELECT 
    p.IdPrzesylki,
    p.StatusPrzesylki,
    p.WyliczonaOplata,
    -- Dane z Oracle (Linked Server ORA-ACCT)
    f.numer_faktury AS Oracle_NumerFaktury,
    f.kwota_brutto AS Oracle_KwotaBrutto,
    -- Dane z Access (Linked Server ACC-LOCAL)
    a.IdNadania AS Access_IdNadania,
    a.DataNadania AS Access_DataNadania,
    -- Dane z Excela (Linked Server XLS-RAPORTY)
    e.SumaDostaw AS Excel_SumaDostaw,
    e.Miesiac AS Excel_Miesiac
FROM Przesylki p
LEFT JOIN [ORA-ACCT]..[COURIER_ADMIN].[FAKTURY] f ON p.IdPrzesylki = f.id_przesylki
LEFT JOIN [ACC-LOCAL]...Nadania a ON p.IdKlientaNadawcy = a.IdKlienta
LEFT JOIN [XLS-RAPORTY]...[Sheet1$] e ON e.Miesiac = CONVERT(VARCHAR(7), GETDATE(), 120);
GO

-- =========================================================================
-- 4. usp_GenerujRaportKonsolidacyjny
-- Procedura agregująca dane z wielu węzłów jednocześnie (wielodostęp heterogeniczny).
-- Łączy dane lokalne z tabelami z Oracle, Access oraz Excela.
-- Wykorzystuje funkcje agregujące oraz jawne rzutowanie typów (CAST) w celu
-- ujednolicenia typów danych pochodzących z różnych sterowników.
-- =========================================================================
CREATE OR ALTER PROCEDURE usp_GenerujRaportKonsolidacyjny
    @DataOd DATETIME,
    @DataDo DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        k.IdKlienta,
        k.NazwaFirmy_ImieNazwisko,
        
        -- Agregacja lokalna (liczba przesyłek)
        COUNT(DISTINCT p.IdPrzesylki) AS LiczbaPrzesylekLokalnych,
        
        -- Agregacja i rzutowanie danych zdalnych z Oracle (kwoty faktur)
        CAST(ISNULL(SUM(f.kwota_brutto), 0) AS DECIMAL(10,2)) AS SumaFakturOracle,
        
        -- Agregacja danych zdalnych z bazy MS Access
        COUNT(DISTINCT a.IdNadania) AS LiczbaNadanAccess,
        
        -- Agregacja i rzutowanie danych zdalnych z arkusza Excel
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
