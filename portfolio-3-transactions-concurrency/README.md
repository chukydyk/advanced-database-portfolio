# Portfolio 3: Transactions and Concurrency

**Case study:** The Homes Hotel Chain
**DBMS:** PostgreSQL 15+ (tested on 16)
**Builds on:** Portfolio 1 schema and the Portfolio 2 dataset

## 1. Purpose
Show, with reproducible evidence, that I understand how a database keeps a booking system correct when things fail (transactions: commit, rollback, savepoints) and when many people work at once (isolation levels, locking, deadlocks).

## 2. Folder contents
| Path | What it is |
|---|---|
| `sql/01_setup.sql` | Creates the `sp_make_booking` procedure, four small `demo_*` tables and a `demo_reset()` helper |
| `sql/02_commit_rollback.sql` | Single-session demos T1 to T6: COMMIT, ROLLBACK, SAVEPOINT, stored procedure, durability settings |
| `scripts/run_two_session_demos.sh` | Runs two psql sessions (A and B) at the same time for demos D1 to D7 |
| |`results/` | Saved output |
| `screenshots/` | Terminal screenshots (evidence) |

## 3. ACID mapping
| Property | Where it is shown |
|---|---|
| Atomicity | T1, T2, T3, T4, T5 |
| Consistency | Constraints rejecting bad data: T2, T5c, T5d, D2a |
| Isolation | D1, D4, D5 |
| Durability | T6 (`synchronous_commit`, `wal_level`, `fsync`) |

## 4. Single-session demos (`02_commit_rollback.sql`)
| # | Scenario | Expected result |
|---|---|---|
| T1 | Four dependent inserts (booking, room, invoice, deposit) then COMMIT | Counts rise by one in each table and stay up |
| T2 | Same unit of work, but the deposit uses a non-existent payment method | Error, then "transaction is aborted"; after ROLLBACK counts are unchanged |
| T3 | Guest abandons checkout, ROLLBACK by choice | Row visible inside the transaction, gone afterwards |
| T4 | SAVEPOINT around an optional spa order that fails | Booking kept, failed order undone |
| T5a to T5d | `sp_make_booking`: valid call, overlapping dates, too many guests, bad dates | One success; three errors with no partial rows saved |
| T6 | Durability settings | `synchronous_commit on`, `fsync on` |

## 5. Two-session demos (`run_two_session_demos.sh`)
| Demo | Problem or mechanism | Expected result |
|---|---|---|
| D1a | **Lost update**: both sessions read 1000, A writes +100, B writes +200 | Final balance 1200, but the correct balance is 1300 |
| D1b | Fix 1: atomic `SET points = points + n` | 1300 (B waits for A) |
| D1c | Fix 2: `SELECT ... FOR UPDATE` (pessimistic locking) | 1300 (B waits, then reads 1100) |
| D1d | Fix 3: REPEATABLE READ | B gets "could not serialize access"; balance 1100; B must retry |
| D2a | **Last-room race**: A inserts but has not committed; B tries an overlapping stay | B waits, then the exclusion constraint rejects B |
| D2b | Same race, but A rolls back | B waits, then succeeds |
| D3 | Same race through `sp_make_booking` | B waits on the room lock, then gets "Room 3 is not available"; only one booking, invoice and payment exist |
| D4a | **Dirty read** at READ UNCOMMITTED | B sees the original value: PostgreSQL never exposes uncommitted data |
| D4b | **Non-repeatable read** at READ COMMITTED vs REPEATABLE READ | Two different values vs the same value twice |
| D4c | **Phantom read** at READ COMMITTED vs REPEATABLE READ | Count changes 5 to 6 vs stays 5 |
| D5a | **Write skew** at REPEATABLE READ (rule: at least one receptionist on duty) | Both leave, 0 on duty: rule broken |
| D5b | Same at SERIALIZABLE | One transaction is aborted, 1 on duty: rule holds |
| D6a | **Deadlock**: A locks room 1 then 2, B locks room 2 then 1 | "deadlock detected"; one session is aborted (which one can vary) |
| D6b | Deadlock avoided by locking in a fixed order | No error; B simply waits |
| D7 | `FOR UPDATE` vs `FOR UPDATE SKIP LOCKED` for "next free room" | `FOR UPDATE`: B waits and gets the same room. `SKIP LOCKED`: B immediately gets another room |

### Isolation level summary (PostgreSQL)
| Level | Dirty read | Non-repeatable read | Phantom read | Write skew |
|---|---|---|---|---|
| READ UNCOMMITTED (acts as READ COMMITTED) | No | Possible | Possible | Possible |
| READ COMMITTED (default) | No | Possible | Possible | Possible |
| REPEATABLE READ | No | No | No (snapshot) | Possible |
| SERIALIZABLE | No | No | No | No (one transaction aborted) |

## 6. Screenshot checklist (save in `screenshots/`)
- [ ] `01-setup-complete.png`: end of `01_setup.sql`
- [ ] `02-t1-commit.png`: counts before, inside and after COMMIT
- [ ] `03-t2-rollback.png`: the error, "transaction is aborted", and unchanged counts
- [ ] `04-t4-savepoint.png`
- [ ] `05-t5-procedure.png`: the friendly errors with unchanged counts
- [ ] `06-d1a-lost-update.png`: final 1200 against correct 1300
- [ ] `07-d1b-d1c-fixes.png`
- [ ] `08-d2a-last-room-race.png`: B rejected by the exclusion constraint
- [ ] `09-d4b-isolation.png`: READ COMMITTED vs REPEATABLE READ
- [ ] `10-d5-write-skew.png`: 0 on duty vs 1 on duty
- [ ] `11-d6a-deadlock.png` and `12-d6b-ordered-locks.png`

## 8. Analysis 
Atomicity: In T2 the final insert failed because the payment method did not exist, and after ROLLBACK the row counts matched the starting counts exactly. The failing calls to sp_make_booking in T5 also left no partial rows. A booking without its invoice and deposit would leave the hotel holding a reservation it cannot bill, so the four inserts must succeed or fail together.

Lost update: At READ COMMITTED, both sessions read 1000 before either wrote. A wrote 1100, then B overwrote it with 1200, so the balance ended at 1200 instead of 1300 (D1a). The atomic points = points + n update is the simplest and fastest fix. FOR UPDATE suits logic that must sit between the read and the write, but it makes other sessions wait. REPEATABLE READ aborted B (D1d) and kept locks short, but the application must retry.

Last room: In D2a, B waited for A and was then rejected by the exclusion constraint. In D3, sp_make_booking locked the room row, so B queued and received a clear “Room 3 is not available” message. The lock gives an orderly queue and friendly errors. The constraint guarantees correctness even if some code path forgets the lock.

Isolation levels: PostgreSQL never exposed uncommitted data, even at READ UNCOMMITTED (D4a). Non-repeatable and phantom reads occurred at READ COMMITTED but not at REPEATABLE READ (D4b, D4c). REPEATABLE READ still allowed write skew, leaving zero receptionists on duty (D5a). SERIALIZABLE aborted one transaction (D5b), so applications must be ready to retry.

Deadlocks: In D6a, opposite lock orders formed a cycle. PostgreSQL detected it and aborted one session. In D6b, locking in the same order meant one session simply waited.

Costs and limitations: Concurrency control costs waiting, aborted work and lower throughput. These demos used one server, scripted pauses, two simulated users and small tables, so they show behaviour rather than real load.

## 9. Reflection
The hardest part was setting up the environment, not the SQL: fixing the psql path in Git Bash, confusing -o with -0, and resolving a Git history conflict taught me to check each command carefully and to pull before pushing.

## 10. AI-use declaration
Used AI to debug git bash command 
