-- Procedury składowane
CREATE OR REPLACE PROCEDURE usp_WystawFakture (
    p_id_klienta IN NUMBER,
    p_numer_faktury IN VARCHAR2,
    p_kwota_netto IN NUMBER,
    p_kwota_vat IN NUMBER,
    p_kwota_brutto IN NUMBER,
    p_id_przesylki IN NUMBER DEFAULT NULL
)
AS
BEGIN
    INSERT INTO Faktury (numer_faktury, id_klienta, id_przesylki, kwota_netto, kwota_vat, kwota_brutto)
    VALUES (p_numer_faktury, p_id_klienta, p_id_przesylki, p_kwota_netto, p_kwota_vat, p_kwota_brutto);
EXCEPTION
    WHEN OTHERS THEN
        RAISE_APPLICATION_ERROR(-20001, 'Błąd podczas wystawiania faktury: ' || SQLERRM);
END usp_WystawFakture;
/

CREATE OR REPLACE PROCEDURE usp_RozliczKuriera (
    p_id_kuriera IN NUMBER,
    p_okres IN VARCHAR2,
    p_kwota_prowizji IN NUMBER
)
AS
BEGIN
    INSERT INTO RozliczeniaKurierskie (id_kuriera, okres_rozliczeniowy, kwota_prowizji, status_rozliczenia)
    VALUES (p_id_kuriera, p_okres, p_kwota_prowizji, 'ZATWIERDZONE');
EXCEPTION
    WHEN OTHERS THEN
        RAISE_APPLICATION_ERROR(-20002, 'Błąd podczas rozliczania kuriera: ' || SQLERRM);
END usp_RozliczKuriera;
/

-- Generowanie raportu finansowego
CREATE OR REPLACE PROCEDURE usp_GenerujRaportFinansowy (
    p_data_od IN DATE,
    p_data_do IN DATE,
    p_suma_netto OUT NUMBER,
    p_suma_brutto OUT NUMBER,
    p_suma_platnosci OUT NUMBER
)
AS
BEGIN
    SELECT NVL(SUM(kwota_netto), 0), NVL(SUM(kwota_brutto), 0)
    INTO p_suma_netto, p_suma_brutto
    FROM Faktury
    WHERE data_wystawienia BETWEEN p_data_od AND p_data_do;

    SELECT NVL(SUM(kwota), 0)
    INTO p_suma_platnosci
    FROM Platnosci
    WHERE data_platnosci BETWEEN p_data_od AND p_data_do;
    
EXCEPTION
    WHEN OTHERS THEN
        p_suma_netto := 0;
        p_suma_brutto := 0;
        p_suma_platnosci := 0;
        RAISE_APPLICATION_ERROR(-20003, 'Błąd podczas generowania raportu finansowego: ' || SQLERRM);
END usp_GenerujRaportFinansowy;
/
