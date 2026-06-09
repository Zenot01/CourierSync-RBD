-- Oracle Cennik
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
