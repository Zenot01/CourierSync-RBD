# Dokumentacja Techniczna: Transakcje Rozproszone (MS DTC) i Replikacja

Niniejszy dokument zawiera opis teoretyczny oraz instrukcje konfiguracyjne dla transakcji rozproszonych i mechanizmów replikacji danych zaimplementowanych w projekcie CourierSync-RBD.

---

## 1. Transakcje Rozproszone i MS DTC

Transakcja rozproszona to transakcja obejmująca modyfikację danych na co najmniej dwóch różnych serwerach bazodanowych (węzłach). Aby zapewnić spójność danych (zasada ACID) na wszystkich serwerach, stosuje się protokół **dwufazowego zatwierdzania (Two-Phase Commit - 2PC)** koordynowany przez usługę **Microsoft Distributed Transaction Coordinator (MS DTC)**.

### Jak działa Protokół Dwufazowego Zatwierdzania (2PC)?
Proces ten dzieli się na dwie główne fazy:

1.  **Faza 1: Przygotowanie (Prepare Phase):**
    *   Koordynator (MS DTC na serwerze SQLServer-HQ) wysyła zapytanie do wszystkich uczestników transakcji (SQLServer-REG i Oracle-ACCT) z pytaniem, czy są gotowi zapisać zmiany.
    *   Każdy serwer bazodanowy wykonuje operacje w pamięci podręcznej, blokuje odpowiednie zasoby i zapisuje logi transakcyjne na dysk.
    *   Jeżeli serwer może zapisać zmiany bez błędów, wysyła odpowiedź **VOTE_COMMIT** (gotowy). W przeciwnym razie wysyła **VOTE_ABORT** (błąd).

2.  **Faza 2: Zatwierdzenie (Commit Phase):**
    *   Jeżeli **wszystkie** serwery odpowiedziały twierdząco (`VOTE_COMMIT`), MS DTC wysyła do nich rozkaz ostatecznego zatwierdzenia zmian. Serwery zapisują dane trwale (COMMIT) i zwalniają blokady.
    *   Jeżeli chociaż **jeden** serwer zgłosił błąd (`VOTE_ABORT`) lub nie odpowiedział na czas, MS DTC wysyła polecenie wycofania zmian (**ROLLBACK**) do wszystkich węzłów. Żadne dane nie zostają zmienione.

> [!WARNING]
> Właśnie dlatego procedury Oracle (`usp_WystawFakture` i `usp_RozliczKuriera`) nie mogą zawierać słów kluczowych `COMMIT` ani `ROLLBACK`. Wykonanie ich lokalnie w Oracle podczas Fazy 1 przerwałoby protokół dwufazowy i spowodowało błąd `ORA-02074`.

---

## 2. Instrukcja konfiguracji MS DTC w systemie Windows

Aby transakcje rozproszone pomiędzy MS SQL Server a bazą Oracle oraz drugim SQL Serverem mogły przebiegać prawidłowo, usługa MS DTC musi być odpowiednio skonfigurowana na serwerach z systemem Windows.

### Krok po kroku:
1.  Naciśnij kombinację klawiszy `Win + R`, wpisz `dcomcnfg` i zatwierdź klawiszem Enter. Otworzy się konsola **Component Services** (Usługi składowe).
2.  W drzewie po lewej stronie przejdź do:
    `Component Services` -> `Computers` -> `My Computer` -> `Distributed Transaction Coordinator`.
3.  Kliknij prawym przyciskiem myszy na **Local DTC** i wybierz **Properties** (Właściwości).
4.  Przejdź do zakładki **Security** (Zabezpieczenia) i ustaw następujące opcje:
    *   Zaznacz **Network DTC Access** (Dostęp sieciowy DTC).
    *   W sekcji *Client and Administration* zaznacz **Allow Remote Clients** oraz **Allow Remote Administration**.
    *   W sekcji *Transaction Manager Communication* zaznacz **Allow Inbound** (Zezwalaj na przychodzące) oraz **Allow Outbound** (Zezwalaj na wychodzące).
    *   Zaznacz opcję **No Authentication Required** (Brak wymaganej autoryzacji) - zalecane dla środowisk heterogenicznych (SQL Server - Oracle).
    *   **KRYTYCZNE DLA ORACLE:** Zaznacz **Enable XA Transactions** (Włącz transakcje XA). Protokół XA jest standardem przemysłowym dla transakcji rozproszonych w Oracle.
    *   Zaznacz **Enable SNA LU 6.2 Transactions**.
5.  Zatwierdź klikając **Apply** i **OK**. System wyświetli ostrzeżenie o konieczności restartu usługi MS DTC - kliknij **Yes** (Tak).

### Konfiguracja Zapory sieciowej (Firewall):
Należy upewnić się, że na obu serwerach (SQL Server i Oracle) zapora Windows Firewall zezwala na ruch dla:
*   Portu **135** (RPC Endpoint Mapper).
*   Programu `%SystemRoot%\System32\msdtc.exe`.
*   Dynamicznie przydzielanych portów RPC (zaleca się ograniczenie zakresu portów RPC w rejestrze systemowym dla środowisk produkcyjnych).

---

## 3. Architektura Replikacji w CourierSync

Zgodnie z wymaganiami projektowymi, system wykorzystuje dwa rodzaje replikacji:

### A. Replikacja Transakcyjna (Transactional Replication)
*   **Kierunek:** `SQLSRV-HQ` (Warszawa) -> `SQLSRV-REG` (Kraków)
*   **Tabele objęte replikacją:** `Klienci`, `Zamowienia`, `Przesylki`
*   **Zasada działania:** Agent Odczytu Logu (Log Reader Agent) stale monitoruje plik logu transakcyjnego bazy `WarszawaHQ`. Kiedy wykryje nowe transakcje `INSERT/UPDATE/DELETE` na replikowanych tabelach, przesyła je na serwer w Krakowie do bazy `KrakowHQ`.
*   **Uzasadnienie biznesowe:** Kurierzy w terenie przypisani do oddziału w Krakowie muszą dysponować aktualnymi danymi o klientach i przesyłkach w czasie zbliżonym do rzeczywistego (Near Real-Time), aby sprawnie realizować doręczenia.

### B. Replikacja Migawkowa (Snapshot Replication)
*   **Kierunek:** `ORA-ACCT` (Oracle) -> `SQLSRV-HQ` (Warszawa)
*   **Tabele objęte replikacją:** `Cennik`
*   **Zasada działania:** Zrealizowana za pomocą dedykowanej procedury `usp_SynchronizujCennikOracle` wywoływanej raz na dobę przez SQL Server Agent Job (`Replikacja_Cennika_Oracle_Snapshot` o godzinie 01:00). Procedura pobiera cały cennik z Oracle przy użyciu połączenia ad-hoc `OPENROWSET` i nadpisuje lokalną tabelę `Cennik_Replica`.
*   **Uzasadnienie biznesowe:** Cennik usług kurierskich zmienia się rzadko (np. raz na miesiąc). Kopiowanie cennika do lokalnej bazy centrali raz na dobę eliminuje konieczność ciągłego odpytywania bazy Oracle podczas szybkiego wyceniania paczek (zapobiega to zbędnemu obciążeniu łączy i serwerów bazodanowych).

---

## 4. Instrukcja Konfiguracji Replikacji Transakcyjnej przez GUI (SSMS)

Poniższa instrukcja krok po kroku opisuje, jak ręcznie skonfigurować replikację transakcyjną za pomocą kreatorów graficznych w programie SQL Server Management Studio (SSMS).

### Krok 1: Konfiguracja Dystrybutora (Distribution)
Replikacja wymaga serwera dystrybucyjnego. Konfigurujemy go na węźle centralnym (`SQLSRV-HQ`):
1. Połącz się z instancją **SQLSRV-HQ** w SSMS.
2. W oknie *Object Explorer* kliknij prawym przyciskiem myszy folder **Replication** i wybierz **Configure Distribution...**
3. W kreatorze *Configure Distribution Wizard* kliknij *Next*.
4. Wybierz opcję: `SQLSRV-HQ will act as its own Distributor...` (serwer będzie swoim własnym dystrybutorem) i kliknij *Next*.
5. Wskaż folder migawek (Snapshot Folder). Domyślnie jest to lokalna ścieżka np. `C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\ReplData`. Kliknij *Next*.
   > [!IMPORTANT]
   > Upewnij się, że usługa SQL Server Agent oraz SQL Server mają pełne uprawnienia do zapisu i odczytu w tym folderze.
6. Określ nazwę bazy dystrybucyjnej (domyślnie `distribution`) oraz ścieżki dla jej plików danych i logu. Kliknij *Next*.
7. W oknie *Publishers* upewnij się, że lokalny serwer jest zaznaczony jako wydawca. Kliknij *Next*.
8. Zaznacz opcję **Configure distribution** i kliknij *Next*, a następnie **Finish**, aby zakończyć proces konfiguracji dystrybutora.

### Krok 2: Utworzenie Publikacji (Publication)
Publikacja definiuje bazy i tabele (artykuły), które będą wysyłane do oddziału regionalnego:
1. W *Object Explorer* rozwiń folder **Replication**, kliknij prawym przyciskiem myszy **Local Publications** i wybierz **New Publication...**
2. W kreatorze *New Publication Wizard* kliknij *Next*.
3. Wybierz bazę danych **WarszawaHQ** jako bazę publikacji i kliknij *Next*.
4. Jako typ publikacji (*Publication Type*) zaznacz **Transactional publication** i kliknij *Next*.
5. W oknie wyboru artykułów (*Articles*) zaznacz tabele, które mają podlegać replikacji:
   * `dbo.Klienci`
   * `dbo.Zamowienia`
   * `dbo.Przesylki`
   Kliknij *Next*.
6. W oknie *Filter Table Rows* nie dodawaj żadnych filtrów (chcemy replikować całe tabele). Kliknij *Next*.
7. Zaznacz opcję **Create a snapshot immediately and keep the snapshot available to initialize subscriptions** (wygeneruj migawkę początkową natychmiast) i kliknij *Next*.
8. Skonfiguruj zabezpieczenia agenta migawek (*Agent Security*):
   * Kliknij **Security Settings...**
   * Wybierz konto, z którego będzie korzystać Agent (np. konto usługi SQL Server Agent – zaznacz *Run under the SQL Server Agent service account*).
   * Dla połączenia z wydawcą zaznacz połączenie przez zabezpieczenia zintegrowane (*By impersonating the process account*). Kliknij *OK*, a potem *Next*.
9. Wybierz **Create the publication** i kliknij *Next*.
10. Nadaj publikacji nazwę **Pub_KlienciZamowieniaPrzesylki** i kliknij **Finish**.

### Krok 3: Utworzenie Subskrypcji typu Push (Subscription)
Subskrypcja definiuje odbiorcę (serwer regionalny) oraz bazę docelową:
1. W *Object Explorer* rozwiń **Replication** -> **Local Publications**, kliknij prawym przyciskiem myszy na nowo utworzoną publikację **Pub_KlienciZamowieniaPrzesylki** i wybierz **New Subscriptions...**
2. W kreatorze *New Subscription Wizard* kliknij *Next*.
3. Upewnij się, że zaznaczona jest odpowiednia publikacja i kliknij *Next*.
4. Wybierz lokalizację uruchomienia agenta dystrybucji. Zaznacz pierwszą opcję: **Run all agents at the Distributor (push subscriptions)**. Pozwoli to na centralne monitorowanie i zarządzanie replikacją z poziomu centrali. Kliknij *Next*.
5. W sekcji *Subscribers* kliknij przycisk **Add Subscriber** -> **Add SQL Server Subscriber...** i połącz się z instancją serwera regionalnego **SQLSRV-REG**.
6. W kolumnie *Subscription Database* dla serwera **SQLSRV-REG** wybierz bazę docelową **KrakowHQ**. Kliknij *Next*.
7. Skonfiguruj zabezpieczenia agenta dystrybucji (*Distribution Agent Security*):
   * Kliknij przycisk z wielokropkiem (`...`) dla subskrybenta **SQLSRV-REG**.
   * Wybierz uruchamianie pod kontem usługi SQL Server Agent dystrybutora (*Run under the SQL Server Agent service account*).
   * Do połączenia z dystrybutorem i subskrybentem wybierz *By impersonating the process account*. Kliknij *OK*, a potem *Next*.
8. Ustaw harmonogram synchronizacji (*Synchronization Schedule*) na **Run continuously** (praca ciągła w tle, zapewniająca synchronizację w czasie niemal rzeczywistym). Kliknij *Next*.
9. W oknie *Initialize Subscriptions* upewnij się, że zaznaczone je **Initialize** -> **Immediately** (inicjalizacja natychmiastowa poprzez wgranie migawki początkowej). Kliknij *Next*.
10. Wybierz opcję **Create the subscription(s)** i kliknij *Next*, a następnie **Finish**.

Po zakończeniu kreatora, SQL Server Agent automatycznie uruchomi procesy generowania migawki i przeniesienia danych do bazy regionalnej.

---

## 5. Rozwiązywanie problemów (Troubleshooting) i awarie SQL Server

### Błąd: "A transport-level error has occurred when receiving results..." (Potok został zakończony)
Jeśli podczas uruchamiania procedury z transakcją rozproszoną (np. `usp_PotwierdzDoreczenie`) usługa SQL Server gwałtownie się wyłącza, a w programie SSMS pojawia się błąd o przerwaniu połączenia sieciowego (błąd 109, Shared Memory Provider), oznacza to **awarię procesu serwera bazodanowego**.

#### Przyczyna:
Sterownik OLE DB `OraOLEDB.Oracle` domyślnie próbuje załadować się wewnątrz pamięci SQL Server (`AllowInProcess = 1`). Jeśli na maszynie nie jest prawidłowo skonfigurowana usługa MS DTC w systemie Windows lub brakuje komponentu **Oracle Services for Microsoft Transaction Server (OraMTS)**, sterownik Oracle podczas próby rejestracji w transakcji generuje błąd ochrony pamięci (Access Violation), co powoduje natychmiastowe ubicie całej instancji SQL Server.

#### Rozwiązanie (Izolacja procesu sterownika):
Najbezpieczniejszym rozwiązaniem zapobiegającym awariom serwera jest uruchomienie dostawcy Oracle w osobnym procesie (out-of-process). Wtedy ewentualny błąd sterownika spowoduje jedynie zrzucenie błędu transakcji i wycofanie zmian, a nie wyłączenie serwera SQL:

1. W SSMS rozwiń **Server Objects** -> **Linked Servers** -> **Providers**.
2. Kliknij prawym przyciskiem myszy na **OraOLEDB.Oracle** i wybierz **Properties**.
3. **Odznacz** opcję **Allow inprocess** (zezwól na uruchamianie w procesie).
4. Zapisz zmiany.

Można to również wykonać za pomocą T-SQL:
```sql
EXEC master.dbo.sp_MSset_oledb_prop N'OraOLEDB.Oracle', N'AllowInProcess', 0;
```

> [!NOTE]
> Uruchomienie out-of-process sprawia, że błędy są poprawnie przechwytywane przez blok `TRY...CATCH` w skrypcie `06_example_usage.sql` i zamiast awarii bazy otrzymamy bezpieczny komunikat diagnostyczny:
> `Uwaga: Blad podczas wywolania transakcji rozproszonej usp_PotwierdzDoreczenie.`

#### Prawidłowa konfiguracja transakcji rozproszonej w Oracle:
Jeśli chcesz, aby transakcje rozproszone z Oracle działały poprawnie (a nie tylko zwracały bezpieczny błąd), musisz:
1. Zainstalować komponent **Oracle Services for MTS** podczas instalacji Oracle Client (instalator ODAC/Oracle Client). Komponent ten tworzy usługę systemową w Windows o nazwie `OracleMTSRecoveryService`.
2. Upewnić się, że usługa `OracleMTSRecoveryService` jest uruchomiona.
3. Włączyć obsługę transakcji XA w konfiguracji MS DTC (`Enable XA Transactions` w `dcomcnfg`).
4. W takim docelowym środowisku produkcyjnym sterownik `OraOLEDB.Oracle` może wymagać powrotnego włączenia opcji `AllowInProcess` na `1`.
