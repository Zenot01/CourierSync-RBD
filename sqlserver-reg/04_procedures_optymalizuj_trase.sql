USE KrakowHQ;
GO

-- usp_OptymalizujTrase: Wyznacza optymalną trasę i generuje LIFO.

CREATE OR ALTER PROCEDURE usp_OptymalizujTrase
    @IdKuriera INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Pobranie aktywnego przydziału kuriera na dziś
    DECLARE @IdPrzydzialu INT;
    DECLARE @IdTrasy INT;
    DECLARE @LiczbaEtapow INT;

    SELECT TOP 1
        @IdPrzydzialu = pk.IdPrzydzialu,
        @IdTrasy      = pk.IdTrasy
    FROM PrzydzialyKurierow pk
    WHERE pk.IdKuriera = @IdKuriera
      AND pk.DataPrzydzialu = CAST(GETDATE() AS DATE)
    ORDER BY pk.IdPrzydzialu DESC;

    IF @IdPrzydzialu IS NULL
    BEGIN
        RAISERROR('Brak aktywnego przydziału kuriera %d na dziś.', 16, 1, @IdKuriera);
        RETURN;
    END;

    -- Sprawdzenie liczby etapów trasy
    SELECT @LiczbaEtapow = COUNT(*)
    FROM EtapyTrasy
    WHERE IdTrasy = @IdTrasy;

    IF @LiczbaEtapow = 0
    BEGIN
        RAISERROR('Trasa %d nie ma zdefiniowanych żadnych etapów (przystanków).', 16, 1, @IdTrasy);
        RETURN;
    END;

    -- Pobranie nieodebranych przesyłek z HQ przez dynamiczny OPENQUERY
    CREATE TABLE #TempHQ (
        IdPrzesylki         INT,
        IdSortowniDocelowej INT
    );

    DECLARE @SqlHQ NVARCHAR(1000);
    SET @SqlHQ = N'
        INSERT INTO #TempHQ (IdPrzesylki, IdSortowniDocelowej)
        SELECT p.IdPrzesylki, p.IdSortowniDocelowej
        FROM OPENQUERY([SQLSRV-HQ],
            ''SELECT IdPrzesylki, IdSortowniDocelowej
              FROM WarszawaHQ.dbo.Przesylki
              WHERE StatusPrzesylki = ''''DO_DORECZENIA''''
                AND IdKuriera = ' + CAST(@IdKuriera AS NVARCHAR(10)) + ''')';

    EXEC sp_executesql @SqlHQ;

    -- Powiązanie przesyłek z etapami trasy
    DECLARE @Przesylki TABLE (
        IdPrzesylki          INT,
        KolejnoscRozladunku  INT,  -- Kolejność dostawy (1 = pierwsza)
        KolejnoscZaladunku   INT,  -- Kolejność załadunku (odwrotne LIFO)
        SektorTira           VARCHAR(20)
    );

    INSERT INTO @Przesylki (IdPrzesylki, KolejnoscRozladunku)
    SELECT
        hq.IdPrzesylki,
        ISNULL(et.KolejnoscRozladunku, @LiczbaEtapow + 1)
    FROM #TempHQ hq
    LEFT JOIN EtapyTrasy et
        ON et.IdTrasy    = @IdTrasy
       AND et.IdSortowni = hq.IdSortowniDocelowej;

    DROP TABLE #TempHQ;

    IF NOT EXISTS (SELECT 1 FROM @Przesylki)
    BEGIN
        PRINT 'Brak przesyłek do doręczenia dla kuriera ' + CAST(@IdKuriera AS VARCHAR(10)) + ' dzisiaj.';
        RETURN;
    END;

    -- Wyznaczenie kolejności załadunku (LIFO) i sektora pojazdu
    ;WITH RankedPaczki AS (
        SELECT
            IdPrzesylki,
            KolejnoscRozladunku,
            ROW_NUMBER() OVER (ORDER BY KolejnoscRozladunku DESC) AS KolejnoscZaladunku
        FROM @Przesylki
    )
    UPDATE p
    SET
        KolejnoscZaladunku = rp.KolejnoscZaladunku,
        SektorTira = CASE
            -- Pierwsza 1/3 trasy -> PRZOD (ładowane na końcu)
            WHEN p.KolejnoscRozladunku <= @LiczbaEtapow / 3
                THEN 'PRZOD'
            -- Ostatnia 1/3 trasy -> TYL (ładowane jako pierwsze)
            WHEN p.KolejnoscRozladunku > (@LiczbaEtapow * 2) / 3
                THEN 'TYL'
            -- Środkowe etapy -> SRODEK
            ELSE 'SRODEK'
        END
    FROM @Przesylki p
    JOIN RankedPaczki rp ON p.IdPrzesylki = rp.IdPrzesylki;

    -- Czyszczenie starego i zapis nowego manifestu
    DELETE FROM ZaladunekPojazdu
    WHERE IdPrzydzialu = @IdPrzydzialu;

    INSERT INTO ZaladunekPojazdu (IdPrzydzialu, IdPrzesylki, KolejnoscZaladunku, SektorTira)
    SELECT
        @IdPrzydzialu,
        IdPrzesylki,
        KolejnoscZaladunku,
        SektorTira
    FROM @Przesylki
    ORDER BY KolejnoscZaladunku;

    -- Pobranie i zwrócenie
    SELECT
        z.KolejnoscZaladunku                        AS [Lp. załadunku],
        z.IdPrzesylki                               AS [ID Przesyłki],
        z.SektorTira                                AS [Sektor tira],
        et.KolejnoscRozladunku                      AS [Kolejność doręczenia],
        t.NazwaTrasy                                AS [Trasa],
        et.IdSortowni                               AS [Strefa doręczenia]
    FROM ZaladunekPojazdu z
    JOIN PrzydzialyKurierow pk ON z.IdPrzydzialu = pk.IdPrzydzialu
    JOIN Trasy t               ON t.IdTrasy      = pk.IdTrasy
    JOIN EtapyTrasy et         ON et.IdTrasy     = pk.IdTrasy
    JOIN @Przesylki p          ON p.IdPrzesylki  = z.IdPrzesylki
                               AND et.KolejnoscRozladunku = p.KolejnoscRozladunku
    WHERE z.IdPrzydzialu = @IdPrzydzialu
    ORDER BY z.KolejnoscZaladunku;

    PRINT 'Manifest załadunkowy dla kuriera ' + CAST(@IdKuriera AS VARCHAR(10)) + ' został wygenerowany pomyślnie.';
END;
GO
