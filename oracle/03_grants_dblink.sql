-- 4. Nadanie uprawnień do tabel
-- Dla administratora - pełny dostęp do wszystkich tabel
GRANT ALL PRIVILEGES ON Cennik TO role_admin;
GRANT ALL PRIVILEGES ON Faktury TO role_admin;
GRANT ALL PRIVILEGES ON Platnosci TO role_admin;
GRANT ALL PRIVILEGES ON RozliczeniaKurierskie TO role_admin;

-- Dla aplikacji - zapis i odczyt faktur oraz płatności
GRANT SELECT, INSERT, UPDATE ON Faktury TO role_app;
GRANT SELECT, INSERT, UPDATE ON Platnosci TO role_app;
GRANT SELECT ON Cennik TO role_app;

-- Dla SQL Server Linked Server (tylko odczyt)
GRANT SELECT ON Cennik TO role_ro;
GRANT SELECT ON Faktury TO role_ro;
GRANT SELECT ON Platnosci TO role_ro;
GRANT SELECT ON RozliczeniaKurierskie TO role_ro;

-- Dla replikacji
GRANT SELECT, INSERT, UPDATE, DELETE ON Cennik TO role_rep;
GRANT SELECT, INSERT, UPDATE, DELETE ON Faktury TO role_rep;
GRANT SELECT, INSERT, UPDATE, DELETE ON Platnosci TO role_rep;
GRANT SELECT, INSERT, UPDATE, DELETE ON RozliczeniaKurierskie TO role_rep;

-- =========================================================================
-- BEZPOŚREDNIE UPRAWNIENIA DLA UŻYTKOWNIKÓW (WYMAGANE DLA LINKED SERVER / DB LINK)
-- W Oracle uprawnienia nadane przez role nie działają w połączeniach przez linki.
-- =========================================================================
GRANT SELECT, INSERT, UPDATE ON Faktury TO COURIER_APP;
GRANT SELECT, INSERT, UPDATE ON Platnosci TO COURIER_APP;
GRANT SELECT ON Cennik TO COURIER_APP;

GRANT SELECT ON Cennik TO COURIER_RO;
GRANT SELECT ON Faktury TO COURIER_RO;
GRANT SELECT ON Platnosci TO COURIER_RO;
GRANT SELECT ON RozliczeniaKurierskie TO COURIER_RO;

GRANT SELECT, INSERT, UPDATE, DELETE ON Cennik TO COURIER_REP;
GRANT SELECT, INSERT, UPDATE, DELETE ON Faktury TO COURIER_REP;
GRANT SELECT, INSERT, UPDATE, DELETE ON Platnosci TO COURIER_REP;
GRANT SELECT, INSERT, UPDATE, DELETE ON RozliczeniaKurierskie TO COURIER_REP;

-- Dla audytu (dostęp wyłącznie do widoków raportowych)


-- 5. Database Linki (Symulacja danych rozproszonych w Oracle)
-- Usunięcie istniejących Database Linków w celu uniknięcia konfliktów
DECLARE
  PROCEDURE safe_drop_db_link(p_link IN VARCHAR2, p_is_public IN BOOLEAN) IS
  BEGIN
    IF p_is_public THEN
      EXECUTE IMMEDIATE 'DROP PUBLIC DATABASE LINK ' || p_link;
    ELSE
      EXECUTE IMMEDIATE 'DROP DATABASE LINK ' || p_link;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE != -2024 THEN RAISE; END IF;
  END;
BEGIN
  safe_drop_db_link('hq_link_private', FALSE);
  safe_drop_db_link('hq_link_public', TRUE);
END;
/

-- Prywatny DB Link (używany przez COURIER_REP)
CREATE DATABASE LINK hq_link_private
   CONNECT TO CentralAdminLogin IDENTIFIED BY "HQAdminPassword123!"
   USING 'SQLSRV-HQ';

-- Publiczny DB Link (do celów raportowych)
CREATE PUBLIC DATABASE LINK hq_link_public
   CONNECT TO AppCentralLogin IDENTIFIED BY "HQAppPassword123!"
   USING 'SQLSRV-HQ';
/

-- =========================================================================
-- WERYFIKACJA POŁĄCZENIA DATABASE LINKÓW (Oracle -> SQL Server)
-- =========================================================================
-- Uruchom te zapytania po zaimplementowaniu linków, aby przetestować połączenie:
-- SELECT * FROM dual@hq_link_public;
-- SELECT * FROM dual@hq_link_private;

