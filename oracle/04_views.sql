-- Widoki rozproszone
-- Pobiera Klienci z SQLSRV-HQ przez DB Link
CREATE OR REPLACE VIEW vw_FakturyZKlientami AS
SELECT 
    f.id_faktury,
    f.numer_faktury,
    k."NazwaFirmy_ImieNazwisko" AS nazwa_klienta,
    f.kwota_brutto,
    f.data_wystawienia
FROM Faktury f
JOIN "dbo"."Klienci"@hq_link_public k ON f.id_klienta = k."IdKlienta";

-- Łączenie faktur ze statusami przesyłek z centrali
CREATE OR REPLACE VIEW vw_FakturyStatusyPrzesylek AS
SELECT 
    f.id_faktury,
    f.numer_faktury,
    f.id_klienta,
    f.id_przesylki,
    f.kwota_brutto,
    f.data_wystawienia,
    p."StatusPrzesylki" AS status_przesylki
FROM Faktury f
LEFT JOIN "dbo"."Przesylki"@hq_link_public p ON f.id_przesylki = p."IdPrzesylki";

-- Nadanie uprawnień roli role_audit
GRANT SELECT ON vw_FakturyZKlientami TO role_audit;
GRANT SELECT ON vw_FakturyStatusyPrzesylek TO role_audit;

