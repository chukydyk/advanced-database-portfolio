# Advanced Database Systems Portfolio

**Student:** Chukwuma Dike
**Programme:** MSc Information Technology, Miva Open University
**Case study:** The Homes Hotel Chain (simulated multi-branch hotel reservation system)
**Repository visibility:** Private

## Case study summary
The Homes is a simulated hotel chain with several branches. The database covers guests, rooms, bookings, payments, check-in/check-out records, services, billing, housekeeping, maintenance, loyalty and audit logging. The same case study is used in every portfolio.

## Technology stack
| Purpose | Tool |
|---|---|
| Relational DBMS | PostgreSQL 15+ |
| NoSQL | MongoDB (document model) |
| Distributed / cloud | To be decided (replication and sharding demo, cloud architecture) |
| Version control | Git / GitHub (private) |

## Repository structure
| Folder | Portfolio | Status |
|---|---|---|
| `portfolio-1-database-design/` | Database design and modelling: case study, ER diagram, schema, keys, constraints, normalisation | Draft complete |
| `portfolio-2-query-optimisation/` | Query processing and optimisation: SQL queries, execution plans, indexing, performance analysis | Not started |
| `portfolio-3-transactions-concurrency/` | Transactions and concurrency: commit, rollback, isolation, locking | Not started |
| `portfolio-4-nosql/` | NoSQL and advanced data models | Not started |
| `portfolio-5-distributed-cloud/` | Distributed and cloud database exercise | Not started |
| `docs/` | Final 2-3 page summary, reflection, AI-use declaration | Not started |

## How to run the project
```bash
# 1. Create the database
createdb the_homes

# 2. Load the schema
psql -d the_homes -f portfolio-1-database-design/schema.sql
```
Further steps (sample data, queries, experiments) are added in each portfolio's README as they are completed.

## Work log
| Date | Activity | Evidence |
|---|---|---|
| 2026-10-22 | Chose case study, drafted Portfolio 1 design and schema | `portfolio-1-database-design/` |

## Evidence conventions
- Each portfolio folder has its own `README.md` with purpose, how to run, results and explanation.
- Screenshots go in that folder's `screenshots/` directory, named `NN-short-description.png` (include failures and fixes, not just successes).
- Commit after each completed activity with a clear message, for example `P2: add composite index on booking(hotel_id, check_in_date) with EXPLAIN comparison`.
- No credentials, real personal data, or card numbers are ever committed.

## References
*(Add module references here.)*

## AI-use declaration
*(Complete before submission: state where AI assistance was used, for example drafting the initial schema and documentation, and what you verified, tested, and changed yourself.)*
