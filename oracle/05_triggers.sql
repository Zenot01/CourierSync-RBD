-- Wyzwalacze INSTEAD OF dla widoków rozproszonych
CREATE OR REPLACE TRIGGER trg_vw_FakturyZKlientami_Insert
INSTEAD OF INSERT ON vw_FakturyZKlientami
FOR EACH ROW
BEGIN
    -- Wstawianie faktury z poziomu widoku
    INSERT INTO Faktury (numer_faktury, id_klienta, kwota_netto, kwota_vat, kwota_brutto, data_wystawienia)
    VALUES (
        :NEW.numer_faktury, 
        -- Wyszukanie IdKlienta na zdalnym serwerze
        (SELECT "IdKlienta" FROM "dbo"."Klienci"@hq_link_public WHERE "NazwaFirmy_ImieNazwisko" = :NEW.nazwa_klienta AND ROWNUM = 1),
        ROUND(:NEW.kwota_brutto / 1.23, 2), 
        ROUND(:NEW.kwota_brutto - (:NEW.kwota_brutto / 1.23), 2),
        :NEW.kwota_brutto,
        NVL(:NEW.data_wystawienia, SYSDATE)
    );
END;
/

-- INSTEAD OF INSERT dla statusów przesyłek
CREATE OR REPLACE TRIGGER trg_vw_FakturyStatusy_Insert
INSTEAD OF INSERT ON vw_FakturyStatusyPrzesylek
FOR EACH ROW
BEGIN
    INSERT INTO Faktury (numer_faktury, id_klienta, id_przesylki, kwota_netto, kwota_vat, kwota_brutto, data_wystawienia)
    VALUES (
        :NEW.numer_faktury,
        :NEW.id_klienta,
        :NEW.id_przesylki,
        ROUND(:NEW.kwota_brutto / 1.23, 2),
        ROUND(:NEW.kwota_brutto - (:NEW.kwota_brutto / 1.23), 2),
        :NEW.kwota_brutto,
        NVL(:NEW.data_wystawienia, SYSDATE)
    );
END;
/

-- INSTEAD OF UPDATE dla statusów przesyłek
CREATE OR REPLACE TRIGGER trg_vw_FakturyStatusy_Update
INSTEAD OF UPDATE ON vw_FakturyStatusyPrzesylek
FOR EACH ROW
BEGIN
    -- Aktualizacja lokalnej faktury
    UPDATE Faktury
    SET 
        id_klienta = :NEW.id_klienta,
        id_przesylki = :NEW.id_przesylki,
        kwota_brutto = :NEW.kwota_brutto,
        kwota_netto = ROUND(:NEW.kwota_brutto / 1.23, 2),
        kwota_vat = ROUND(:NEW.kwota_brutto - (:NEW.kwota_brutto / 1.23), 2),
        data_wystawienia = :NEW.data_wystawienia
    WHERE id_faktury = :OLD.id_faktury;
    
    -- Aktualizacja statusu w bazie zdalnej
    IF :NEW.status_przesylki IS NOT NULL AND (:OLD.status_przesylki IS NULL OR :OLD.status_przesylki <> :NEW.status_przesylki) THEN
        UPDATE "dbo"."Przesylki"@hq_link_public
        SET "StatusPrzesylki" = :NEW.status_przesylki
        WHERE "IdPrzesylki" = :NEW.id_przesylki;
    END IF;
END;
/

