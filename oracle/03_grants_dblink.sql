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

-- Dla audytu (dostęp wyłącznie do widoków raportowych)

-- 5. Database Linki (Symulacja danych rozproszonych w Oracle)
-- Prywatny DB Link (używany przez COURIER_REP)
CREATE DATABASE LINK hq_link_private
   CONNECT TO CentralAdminLogin IDENTIFIED BY "HQAdminPassword123!"
   USING 'SQLSRV-HQ';

-- Publiczny DB Link (do celów raportowych)
CREATE PUBLIC DATABASE LINK hq_link_public
   CONNECT TO AppCentralLogin IDENTIFIED BY "HQAppPassword123!"
   USING 'SQLSRV-HQ';
