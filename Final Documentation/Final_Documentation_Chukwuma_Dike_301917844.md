# Final Documentation: Advanced Database Systems Portfolio

**N****am****e****:**** ****Chukwuma Dike**

**Student ID: 301917844**

Dept: MSc Information Technology

Course: MIT 8103 Advanced Database Systems

Repository (public): https://github.com/chukydyk/advanced-database-portfolio

## 1. Selected Organisation

The case study is **The Homes**, a simulated hotel chain with five branches (Abuja, Lagos and Port Harcourt in Nigeria, Accra in Ghana and Nairobi in Kenya) and about 600 rooms. It suits an advanced database project because it combines money-critical transactions (reservations, invoices, payments), many users competing for the same rooms, varied data (guest reviews, preferences, device events) and a multi-country footprint that raises replication, availability and data-residency questions. Because the organisation is simulated, no real employer or guest data was used. The same case study was used in all five portfolios.

## 2. Project Summary

| Portfolio | What was built | Main finding |
| --- | --- | --- |
| 1. Design and modelling | ER diagram and a 24-table, third-normal-form PostgreSQL schema with keys and constraints, including an exclusion constraint that rejects overlapping bookings for the same room | The database itself, not application code, can prevent double booking. Deliberate denormalisation (price snapshots) was justified. |
| 2. Query processing and optimisation | About 221,000 bookings and 403,000 payments of generated data; 12 business queries (joins, CTEs, window functions, ROLLUP); eight before/after experiments with execution plans | Matching indexes to queries (partial, covering, expression) and rewriting a correlated subquery gave the clearest gains. On small tables some indexes helped little. |
| 3. Transactions and concurrency | An all-or-nothing booking procedure; commit, rollback and savepoint demos; two-session demos of a lost update, the last-room race, isolation anomalies, write skew and a deadlock | Transactions kept bookings, invoices and payments consistent. Locks and the constraint protected the last room. Higher isolation and consistent lock ordering prevented anomalies, at the cost of waiting and retries. |
| 4. NoSQL | A MongoDB document model (hotels, guest profiles, reviews, events) exported from PostgreSQL, with schema validation, indexes and aggregation queries; key-value (Redis) examples; a graph model as a design | Documents suit varied data that is read together. Indexes cut documents examined from tens of thousands to hundreds or fewer, for example 50,000 to 1 for an e-mail lookup and 146,031 to 135 for noise alerts. |
| 5. Distributed and cloud databases | A MongoDB replica set with a crash-failover test, consistency and CAP demos; a sharded cluster with country zones; a cloud architecture design | After the primary was crashed, a new one was elected and no acknowledged write was lost. With no majority, the survivor refused writes, choosing consistency. Zoned sharding gave locality but an uneven split. |

**Overall design.** The project ends with a multi-database (polyglot) architecture. PostgreSQL remains the system of record for reservations and money, because it offers constraints and multi-table ACID transactions. MongoDB holds reviews, guest profiles and event logs, whose shape varies. Redis suits temporary room holds and caches. Replication across zones and a disaster-recovery region provide availability, and a synchronous standby protects committed bookings.

**Evidence and limits.** The GitHub repository has one folder per portfolio with SQL scripts, schemas, ER diagrams, NoSQL scripts, execution plans, saved results, screenshots and README files. The graph model, PostgreSQL replication and cloud deployment are designs and were not executed. All servers ran on one computer, so there was no real network delay or partition, and the data is simulated.

## 3. Individual Reflection

This project changed how I see databases: from storing data to protecting it when things fail or collide. The most useful lesson was that guarantees can sit in different layers. In Portfolio 1, an exclusion constraint stopped overlapping reservations. In Portfolio 3, I saw why that matters when two sessions race for the last room, and how locking and the constraint work together. In Portfolio 5, I watched writes pause during an election and then checked that no acknowledged write had disappeared. Reproducing a lost update, write skew and a deadlock on purpose taught me more than reading definitions.

The technical setup was often harder than the SQL. I fixed path problems in Git Bash, a mistyped database name, a confusion between the `-0` and `-o` options, missing MongoDB tools and a Git push rejected because two histories had been created separately. Each problem taught me to read the error carefully, change one thing at a time, pull before pushing and commit in small steps.

The main weaknesses are the single-computer lab and the simulated data. If I repeated the project, I would write the setup checklist first, add automated checks to the scripts, repeat each performance measurement several times, and deploy a managed cloud cluster to measure real cross-region latency.

## 4. AI-Use Declaration

I used an AI assistant (Claude, by Anthropic) to help draft SQL and shell scripts. I ran the scripts on my own computer, produced my own screenshots and results. I am responsible for the submitted work.

## 5. References

Abadi, D. (2012) 'Consistency tradeoffs in modern distributed database system design: CAP is only part of the story', *Computer*, 45(2), pp. 37-42.

Berenson, H., Bernstein, P., Gray, J., Melton, J., O'Neil, E. and O'Neil, P. (1995) 'A critique of ANSI SQL isolation levels', *ACM SIGMOD Record*, 24(2), pp. 1-10.

Brewer, E. (2012) 'CAP twelve years later: how the "rules" have changed', *Computer*, 45(2), pp. 23-29.

Elmasri, R. and Navathe, S. (2016) *Fundamentals of Database Systems*. 7th edn. Harlow: Pearson.

Gilbert, S. and Lynch, N. (2002) 'Brewer's conjecture and the feasibility of consistent, available, partition-tolerant web services', *ACM SIGACT News*, 33(2), pp. 51-59.

Kleppmann, M. (2017) *Designing Data-Intensive Applications*. Sebastopol: O'Reilly Media.

MongoDB, Inc. (2026) *MongoDB Manual*. Available at: https://www.mongodb.com/docs/manual/ (Accessed: October 2026).

PostgreSQL Global Development Group (2026) *PostgreSQL Documentation*. Available at: https://www.postgresql.org/docs/ (Accessed: October 2026).

Redis Ltd (2026) *Redis Documentation*. Available at: https://redis.io/docs/ (Accessed: October 2026).

Silberschatz, A., Korth, H. and Sudarshan, S. (2019) *Database System Concepts*. 7th edn. New York: McGraw-Hill.
