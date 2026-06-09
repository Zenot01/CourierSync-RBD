-- Oracle Cennik
-- Usunięcie istniejących użytkowników i ról w celu uniknięcia konfliktów
DECLARE
  PROCEDURE safe_drop_role(p_role IN VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE 'DROP ROLE ' || p_role;
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE != -1919 THEN RAISE; END IF;
  END;

  PROCEDURE safe_drop_user(p_user IN VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE 'DROP USER ' || p_user || ' CASCADE';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE != -1918 THEN RAISE; END IF;
  END;
BEGIN
  -- Usuwanie użytkowników
  safe_drop_user('COURIER_ADMIN');
  safe_drop_user('COURIER_APP');
  safe_drop_user('COURIER_RO');
  safe_drop_user('COURIER_REP');
  safe_drop_user('COURIER_AUDIT');

  -- Usuwanie ról
  safe_drop_role('role_admin');
  safe_drop_role('role_app');
  safe_drop_role('role_ro');
  safe_drop_role('role_rep');
  safe_drop_role('role_audit');
END;
/

-- 1. Tworzenie Ról
CREATE ROLE role_admin;
CREATE ROLE role_app;
CREATE ROLE role_ro;
CREATE ROLE role_rep;
CREATE ROLE role_audit;

-- 2. Tworzenie Użytkowników
-- Hasła w cudzysłowach wymagane gdy zawierają znaki specjalne (np. !) - Oracle SQL*Plus
CREATE USER COURIER_ADMIN IDENTIFIED BY "AdminSecure123!";
CREATE USER COURIER_APP IDENTIFIED BY "AppSecure123!";
CREATE USER COURIER_RO IDENTIFIED BY "ROSecure123!";
CREATE USER COURIER_REP IDENTIFIED BY "RepSecure123!";
CREATE USER COURIER_AUDIT IDENTIFIED BY "AuditSecure123!";

-- Podstawowe uprawnienia do logowania
GRANT CREATE SESSION TO COURIER_ADMIN, COURIER_APP, COURIER_RO, COURIER_REP, COURIER_AUDIT;

-- 3. Przypisanie użytkowników do ról
GRANT role_admin TO COURIER_ADMIN;
GRANT role_app TO COURIER_APP;
GRANT role_ro TO COURIER_RO;
GRANT role_rep TO COURIER_REP;
GRANT role_audit TO COURIER_AUDIT;
