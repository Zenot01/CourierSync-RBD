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
