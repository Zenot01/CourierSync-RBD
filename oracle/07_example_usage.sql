-- Przykładowe użycie schematu księgowego Oracle (ORA-ACCT)
-- Skrypt uruchamiany w kontekście użytkownika COURIER_ADMIN.
-- Połączenie: COURIER_ADMIN / AdminSecure123! @ rbd2026

SET SERVEROUTPUT ON;
ALTER SESSION SET CURRENT_SCHEMA = COURIER_ADMIN;

-- Weryfikacja i uzupełnianie cennika usług
DELETE FROM Cennik WHERE nazwa_uslugi IN ('STANDARD', 'EXPRESS');

INSERT INTO Cennik (nazwa_uslugi, cena_bazowa, cena_za_kg)
VALUES ('STANDARD', 15.00, 1.80);

INSERT INTO Cennik (nazwa_uslugi, cena_bazowa, cena_za_kg)
VALUES ('EXPRESS', 30.00, 4.00);

COMMIT;

-- Aktualna lista usług w cenniku
SELECT id_uslugi, nazwa_uslugi, cena_bazowa, cena_za_kg FROM Cennik;

-- Wystawienie nowej faktury dla klienta
DECLARE
    v_id_klienta NUMBER := 12;
    v_id_przesylki NUMBER := 301;
    v_nr_faktury VARCHAR2(50);
    v_kwota_brutto NUMBER := 55.00;
    v_kwota_netto NUMBER := ROUND(55.00 / 1.23, 2);
    v_kwota_vat NUMBER := 55.00 - ROUND(55.00 / 1.23, 2);
BEGIN
    v_nr_faktury := 'FV/TEST/' || TO_CHAR(SYSDATE, 'YYYYMMDD') || '/' || TO_CHAR(DBMS_RANDOM.VALUE(1000, 9999), 'FM9999');

    usp_WystawFakture (
        p_id_klienta => v_id_klienta,
        p_numer_faktury => v_nr_faktury,
        p_kwota_netto => v_kwota_netto,
        p_kwota_vat => v_kwota_vat,
        p_kwota_brutto => v_kwota_brutto,
        p_id_przesylki => v_id_przesylki
    );
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Wystawiono fakture: ' || v_nr_faktury);
END;
/

-- Rejestracja wpłaty klienta do wystawionej faktury
DECLARE
    v_id_faktury NUMBER;
    v_kwota NUMBER;
BEGIN
    SELECT id_faktury, kwota_brutto
    INTO v_id_faktury, v_kwota
    FROM (SELECT id_faktury, kwota_brutto FROM Faktury ORDER BY id_faktury DESC)
    WHERE ROWNUM = 1;
    
    INSERT INTO Platnosci (id_faktury, kwota, data_platnosci, metoda_platnosci)
    VALUES (v_id_faktury, v_kwota, SYSDATE, 'KARTA');
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Zarejestrowano platnosc za fakture ID: ' || v_id_faktury || ' na kwote ' || v_kwota || ' PLN.');
END;
/

-- Rozliczenie prowizji kurierskiej
BEGIN
    usp_RozliczKuriera (
        p_id_kuriera => 1,
        p_okres => '2026-06',
        p_kwota_prowizji => 450.00
    );
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Rozliczono prowizje kuriera ID=1 za okres 2026-06.');
END;
/

-- Generowanie raportu finansowego za czerwiec 2026
DECLARE
    v_netto NUMBER;
    v_brutto NUMBER;
    v_platnosci NUMBER;
    v_data_od DATE := TO_DATE('2026-06-01', 'YYYY-MM-DD');
    v_data_do DATE := TO_DATE('2026-06-30', 'YYYY-MM-DD');
BEGIN
    usp_GenerujRaportFinansowy(
        v_data_od,
        v_data_do,
        v_netto,
        v_brutto,
        v_platnosci
    );
    
    DBMS_OUTPUT.PUT_LINE('Raport finansowy (2026-06):');
    DBMS_OUTPUT.PUT_LINE('  - Suma netto:     ' || TO_CHAR(v_netto, '999990.99') || ' PLN');
    DBMS_OUTPUT.PUT_LINE('  - Suma brutto:    ' || TO_CHAR(v_brutto, '999990.99') || ' PLN');
    DBMS_OUTPUT.PUT_LINE('  - Suma platnosci: ' || TO_CHAR(v_platnosci, '999990.99') || ' PLN');
END;
/

-- Odpytywanie widoków rozproszonych (wymaga aktywnego DB Linka hq_link_public)
-- Widok vw_FakturyZKlientami
BEGIN
    FOR rec IN (SELECT * FROM vw_FakturyZKlientami WHERE ROWNUM <= 5) LOOP
        DBMS_OUTPUT.PUT_LINE('Faktura: ' || rec.numer_faktury || ' | Klient: ' || rec.nazwa_klienta || ' | Brutto: ' || rec.kwota_brutto);
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Nie mozna odczytac vw_FakturyZKlientami: ' || SQLERRM);
END;
/

-- Widok vw_FakturyStatusyPrzesylek
BEGIN
    FOR rec IN (SELECT * FROM vw_FakturyStatusyPrzesylek WHERE ROWNUM <= 5) LOOP
        DBMS_OUTPUT.PUT_LINE('Faktura: ' || rec.numer_faktury || ' | Przesylka ID: ' || rec.id_przesylki || ' | Status w HQ: ' || rec.status_przesylki);
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Nie mozna odczytac vw_FakturyStatusyPrzesylek: ' || SQLERRM);
END;
/
