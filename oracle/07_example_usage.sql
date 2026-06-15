-- ========================================================================
-- PRZYKŁADOWE UŻYCIE SCHEMATU KSIĘGOWEGO ORACLE (ORA-ACCT)
-- Skrypt powinien być uruchamiany w kontekście użytkownika COURIER_ADMIN.
-- Połączenie: COURIER_ADMIN / AdminSecure123! @ rbd2026
-- ========================================================================

SET SERVEROUTPUT ON;
ALTER SESSION SET CURRENT_SCHEMA = COURIER_ADMIN;

PROMPT ========================================================================;
PROMPT   SCENARIUSZ TESTOWY DLA BAZY ORACLE (COURIER_ADMIN - KSIĘGOWOŚĆ)
PROMPT ========================================================================;

-- ========================================================================
-- 1. ZAPEWNIENIE DANYCH W CENNIKU
-- ========================================================================

-- Usunięcie starego testowego cennika (opcjonalnie)
DELETE FROM Cennik WHERE nazwa_uslugi IN ('STANDARD', 'EXPRESS');

-- Wstawienie świeżych pozycji cennika
INSERT INTO Cennik (nazwa_uslugi, cena_bazowa, cena_za_kg)
VALUES ('STANDARD', 15.00, 1.80);

INSERT INTO Cennik (nazwa_uslugi, cena_bazowa, cena_za_kg)
VALUES ('EXPRESS', 30.00, 4.00);

COMMIT;

PROMPT Aktualna lista usług w cenniku:;
SELECT id_uslugi, nazwa_uslugi, cena_bazowa, cena_za_kg FROM Cennik;
PROMPT ;

-- ========================================================================
-- 2. WYSTAWIENIE FAKTURY
-- ========================================================================
PROMPT Krok 2: Wystawienie nowej faktury dla klienta...;

DECLARE
    v_id_klienta NUMBER := 12; -- IdKlienta z bazy WarszawaHQ
    v_id_przesylki NUMBER := 301; -- IdPrzesylki z bazy WarszawaHQ
    v_nr_faktury VARCHAR2(50);
    v_kwota_brutto NUMBER := 55.00;
    v_kwota_netto NUMBER := ROUND(55.00 / 1.23, 2);
    v_kwota_vat NUMBER := 55.00 - ROUND(55.00 / 1.23, 2);
    v_exists NUMBER;
BEGIN
    -- Unikalny numer faktury dla testów
    v_nr_faktury := 'FV/TEST/' || TO_CHAR(SYSDATE, 'YYYYMMDD') || '/' || TO_CHAR(DBMS_RANDOM.VALUE(1000, 9999), 'FM9999');

    -- Wywołanie procedury wystawiania faktury
    usp_WystawFakture (
        p_id_klienta => v_id_klienta,
        p_numer_faktury => v_nr_faktury,
        p_kwota_netto => v_kwota_netto,
        p_kwota_vat => v_kwota_vat,
        p_kwota_brutto => v_kwota_brutto,
        p_id_przesylki => v_id_przesylki
    );
    
    -- Zatwierdzamy, ponieważ przy wywołaniu bezpośrednim z poziomu Oracle
    -- musimy ręcznie wykonać COMMIT (gdy wywołuje to MS DTC z SQL Servera,
    -- to DTC dba o zatwierdzenie).
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('  - Pomyślnie wystawiono fakturę: ' || v_nr_faktury);
END;
/
PROMPT ;

-- ========================================================================
-- 3. REJESTRACJA PŁATNOŚCI
-- ========================================================================
PROMPT Krok 3: Rejestracja wpłaty klienta do wystawionej faktury...;

DECLARE
    v_id_faktury NUMBER;
    v_kwota NUMBER;
BEGIN
    -- Pobranie ostatnio wystawionej faktury do testów
    SELECT id_faktury, kwota_brutto
    INTO v_id_faktury, v_kwota
    FROM (SELECT id_faktury, kwota_brutto FROM Faktury ORDER BY id_faktury DESC)
    WHERE ROWNUM = 1;
    
    -- Wstawienie płatności
    INSERT INTO Platnosci (id_faktury, kwota, data_platnosci, metoda_platnosci)
    VALUES (v_id_faktury, v_kwota, SYSDATE, 'KARTA');
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('  - Zarejestrowano płatność za fakturę ID: ' || v_id_faktury || ' na kwotę ' || v_kwota || ' PLN.');
END;
/
PROMPT ;

-- ========================================================================
-- 4. ROZLICZENIE KURIERA (PROWIZJA)
-- ========================================================================
PROMPT Krok 4: Rozliczenie prowizji kurierskiej...;

BEGIN
    -- Wywołanie procedury rozliczenia prowizji kuriera o ID = 1 za czerwiec 2026 r.
    usp_RozliczKuriera (
        p_id_kuriera => 1,
        p_okres => '2026-06',
        p_kwota_prowizji => 450.00
    );
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('  - Rozliczono prowizję kuriera ID=1 za okres 2026-06.');
END;
/
PROMPT ;

-- ========================================================================
-- 5. GENEROWANIE RAPORTU FINANSOWEGO (Z parametrami OUT)
-- ========================================================================
PROMPT Krok 5: Generowanie raportu finansowego za czerwiec 2026...;

DECLARE
    v_netto NUMBER;
    v_brutto NUMBER;
    v_platnosci NUMBER;
    v_data_od DATE := TO_DATE('2026-06-01', 'YYYY-MM-DD');
    v_data_do DATE := TO_DATE('2026-06-30', 'YYYY-MM-DD');
BEGIN
    usp_GenerujRaportFinansowy(
        p_data_od => v_data_od,
        p_data_do => v_data_do,
        p_suma_netto => v_netto,
        p_brutto => v_brutto, -- Uwaga: w nagłówku procedury w 06_procedures.sql parametr nazywa się p_suma_brutto
        p_suma_platnosci => v_platnosci
    );
    
    -- Uwaga: W pliku 06_procedures.sql parametry wyjściowe to:
    -- p_suma_netto OUT NUMBER, p_suma_brutto OUT NUMBER, p_suma_platnosci OUT NUMBER
    -- Użyjmy więc prawidłowych nazw parametrów w wywołaniu pozycyjnym (lub nazwanym):
END;
/

-- Korekta powyższego wywołania na parametry pozycyjne:
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
    DBMS_OUTPUT.PUT_LINE('  - Suma netto z faktur:     ' || TO_CHAR(v_netto, '999990.99') || ' PLN');
    DBMS_OUTPUT.PUT_LINE('  - Suma brutto z faktur:    ' || TO_CHAR(v_brutto, '999990.99') || ' PLN');
    DBMS_OUTPUT.PUT_LINE('  - Suma wpłaconych płatności: ' || TO_CHAR(v_platnosci, '999990.99') || ' PLN');
END;
/
PROMPT ;

-- ========================================================================
-- 6. ODCZYT WIDOKÓW ROZPROSZONYCH
-- ========================================================================
PROMPT Krok 6: Odpytywanie widoków rozproszonych (wymaga aktywnego DB Linka hq_link_public)...;

PROMPT A. Faktury z połączonymi nazwami klientów z centrali (vw_FakturyZKlientami):;
BEGIN
    FOR rec IN (SELECT * FROM vw_FakturyZKlientami WHERE ROWNUM <= 5) LOOP
        DBMS_OUTPUT.PUT_LINE('Faktura: ' || rec.numer_faktury || ' | Klient: ' || rec.nazwa_klienta || ' | Brutto: ' || rec.kwota_brutto);
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('  - [INFO] Nie można odczytać vw_FakturyZKlientami: ' || SQLERRM);
END;
/

PROMPT B. Faktury z połączonymi statusami przesyłek z centrali (vw_FakturyStatusyPrzesylek):;
BEGIN
    FOR rec IN (SELECT * FROM vw_FakturyStatusyPrzesylek WHERE ROWNUM <= 5) LOOP
        DBMS_OUTPUT.PUT_LINE('Faktura: ' || rec.numer_faktury || ' | Przesyłka ID: ' || rec.id_przesylki || ' | Status w HQ: ' || rec.status_przesylki);
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('  - [INFO] Nie można odczytać vw_FakturyStatusyPrzesylek: ' || SQLERRM);
END;
/
