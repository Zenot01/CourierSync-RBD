-- Uprawnienia do tabel
-- role_admin: pełny dostęp
GRANT ALL PRIVILEGES ON Cennik TO role_admin;
GRANT ALL PRIVILEGES ON Faktury TO role_admin;
GRANT ALL PRIVILEGES ON Platnosci TO role_admin;
GRANT ALL PRIVILEGES ON RozliczeniaKurierskie TO role_admin;

-- role_app: zapis/odczyt
GRANT SELECT, INSERT, UPDATE ON Faktury TO role_app;
GRANT SELECT, INSERT, UPDATE ON Platnosci TO role_app;
GRANT SELECT ON Cennik TO role_app;

-- role_ro: tylko odczyt
GRANT SELECT ON Cennik TO role_ro;
GRANT SELECT ON Faktury TO role_ro;
GRANT SELECT ON Platnosci TO role_ro;
GRANT SELECT ON RozliczeniaKurierskie TO role_ro;

-- role_rep: replikacja
GRANT SELECT, INSERT, UPDATE, DELETE ON Cennik TO role_rep;
GRANT SELECT, INSERT, UPDATE, DELETE ON Faktury TO role_rep;
GRANT SELECT, INSERT, UPDATE, DELETE ON Platnosci TO role_rep;
GRANT SELECT, INSERT, UPDATE, DELETE ON RozliczeniaKurierskie TO role_rep;

-- Bezpośrednie uprawnienia dla użytkowników (wymagane dla DB Linków/Linked Server)
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

-- Dla audytu (tylko widoki)


-- Czyszczenie istniejących DB Linków
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

-- Prywatny DB Link
CREATE DATABASE LINK hq_link_private
   CONNECT TO CentralAdminLogin IDENTIFIED BY "HQAdminPassword123!"
   USING 'SQLSRV-HQ';

-- Publiczny DB Link
CREATE PUBLIC DATABASE LINK hq_link_public
   CONNECT TO AppCentralLogin IDENTIFIED BY "HQAppPassword123!"
   USING 'SQLSRV-HQ';
/

-- Test połączenia DB Linków (Oracle -> SQL Server):
-- SELECT * FROM dual@hq_link_public;
-- SELECT * FROM dual@hq_link_private;
