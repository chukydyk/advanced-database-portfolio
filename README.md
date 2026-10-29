# Advanced Database Systems Portfolio

**Student:** Chukwuma Dike
**Programme:** MSc Information Technology, Miva Open University
**Case study:** The Homes Hotel (simulated multi-branch hotel reservation system)
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
| `portfolio-1-database-design/` | Database design and modelling: case study, ER diagram, schema, keys, constraints, normalisation | completed |
| `portfolio-2-query-optimisation/` | Query processing and optimisation: SQL queries, execution plans, indexing, performance analysis | Completed |
| `portfolio-3-transactions-concurrency/` | Transactions and concurrency: commit, rollback, isolation, locking | Completed |
| `portfolio-4-nosql/` | NoSQL and advanced data models | Completed |
| `portfolio-5-distributed-cloud/` | Distributed and cloud database exercise | Completed |
| `docs/` | Final 2-3 page summary, reflection, AI-use declaration | Completed |

## How I run the project
Further steps (sample data, queries, experiments) are added in each portfolio's README as they are completed.

## Work log

| Date | Activity | Problems and fixes | Evidence |
|---|---|---|---|
| 2026-10-22 | Chose the case study (The Homes hotel chain, five branches). Designed the database: ER diagram, 24-table third-normal-form schema, keys and constraints, including an exclusion constraint against double booking | Chose a chain instead of a single hotel to make the distributed work in Portfolio 5 meaningful | `portfolio-1-database-design/` |
| 2026-10-22 | Installed PostgreSQL, ran `schema.sql`, tested the double-booking constraint, exported the ER diagram from pgAdmin. Created the private GitHub repository and pushed Portfolio 1 | Password typing was invisible in psql (normal); `psql` not found in Git Bash, fixed by adding the correct PostgreSQL folder to PATH; a typo in the database name | `screenshots/`, `diagrams/` |
| 2026-10-23 | Portfolio 2: loaded the generated dataset (about 221,000 bookings and 403,000 payments), created the views and ran the 12 business queries | Recreated the database so the test rows from Portfolio 1 did not clash with the generated data | `portfolio-2-query-optimisation/sql/`, `results/` |
| 2026-10-24 | Portfolio 2: ran the eight optimisation experiments twice and saved the execution plans; took screenshots; wrote the performance analysis | Used `-0` instead of `-o`, so no output file was created; reran with the correct option. Pushed with a rejected commit: fixed unrelated Git histories by merging, and removed a Word lock file (`~$README.md`) | `execution-plans/`, `screenshots/` |
| 2026-10-25 | Portfolio 3: created the booking procedure and ran the commit, rollback and savepoint demos; ran the two-session demos (lost update, last-room race, isolation levels, write skew, deadlock) | Learned to capture errors with `> file 2>&1` instead of `-o`, because the errors are the evidence | `portfolio-3-transactions-concurrency/results/`, `screenshots/` |
| 2026-10-26 | Portfolio 4: installed MongoDB tools, exported the PostgreSQL data as documents, created validated collections and imported about 244,000 documents | MongoDB Database Tools were not installed with the server, so I installed them separately and added them to PATH | `portfolio-4-nosql/sql/`, `scripts/` |
| 2026-10-27 | Portfolio 4: ran the index experiments (full scans against index scans), the 11 queries and the update and validation demos; filled in the index table; pushed | `git commit` did nothing until files were staged with `git add .`; checked that the large `.ndjson` files were ignored | `portfolio-4-nosql/results/`, `screenshots/` |
| 2026-10-28 | Portfolio 5: started the replica set, ran the replication demo, the primary-crash failover test, the consistency and CAP demos | Needed `mongod` and `mongos` from the MongoDB Server folder, which is separate from the Tools folder | `portfolio-5-distributed-cloud/results/` |
| 2026-10-29 | Portfolio 5: built and inspected the sharded cluster with country zones; exported the architecture diagram; wrote the analysis and the cloud design | Kept to one cluster at a time because of memory use on the laptop | `results/`, `diagrams/`, `screenshots/` |
| 2026-10-29 | Wrote the final summary report, reflection, references and AI-use declaration; final check of the repository | Checked that the repository is private and that all five portfolio folders show their files | Summary report, GitHub repository |

## Evidence conventions
- Each portfolio folder has its own `README.md` with purpose, how to run, results and explanation.
- Screenshots go in that folder's `screenshots/` directory, named `NN-short-description.png` (include failures and fixes, not just successes).
- No credentials, real personal data, or card numbers are ever committed.


## AI-use declaration
AI was used to generate data, draft the schema and debug. 

