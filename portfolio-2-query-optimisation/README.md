# Portfolio 2: Query Processing and Optimisation

**Case study:** The Homes Hotel Chain (5 branches, 600 rooms)
**DBMS:** PostgreSQL 15+ (tested on 16)
**Builds on:** Portfolio 1 (`portfolio-1-database-design/schema.sql`)

## 1. Purpose
Show that I can write non-trivial SQL against a realistic data volume, read execution plans, and improve performance with evidence (indexes, query rewrites, partitioning, pre-computation).

## 2. Folder contents
| Path | What it is |
|---|---|
| `sql/01_sample_data.sql` | Generates the dataset (fixed random seed, so results are repeatable) |
| `sql/02_queries.sql` | 12 business queries |
| `sql/03_views_functions.sql` | 2 views, 1 materialized view, 1 availability function |
| `sql/04_optimisation_experiments.sql` | 8 before/after experiments with `EXPLAIN (ANALYZE, BUFFERS)` |
| `sql/05_reset_experiments.sql` | Returns the database to its pre-experiment state |
| `results/` | Saved query output |
| `execution-plans/` | Saved execution plans |
| `screenshots/` | Terminal screenshots (evidence) |

## 3. How to run
Open **Git Bash** in this folder. If `psql` is not recognised, add it to the path (change `16` to your version):
```bash
export PATH="$PATH:/c/Program Files/PostgreSQL/16/bin"
```
Then, with the `the_homes` database already created and Portfolio 1's `schema.sql` loaded:
```bash
# 1. Load the sample data (1 to 4 minutes, run ONCE)
psql -U postgres -d the_homes -f sql/01_sample_data.sql

# 2. Views and function
psql -U postgres -d the_homes -f sql/03_views_functions.sql

# 3. The 12 queries, saving their output
psql -U postgres -d the_homes -f sql/02_queries.sql -o results/02_queries_output.txt

# 4. The experiments (run TWICE; keep the second run), saving the plans
psql -U postgres -d the_homes -f sql/04_optimisation_experiments.sql -o execution-plans/04_experiments_output.txt
```
`01_sample_data.sql` must only be run once on an empty schema. To start again, drop and recreate the database, reload `schema.sql`, and repeat.

## 4. Dataset
| Table | Approx. rows |
|---|---|
| booking / booking_room | 221,000 |
| payment | 403,000 |
| invoice | 207,000 |
| stay_record | 192,000 |
| audit_log | 99,000 |
| service_order | 87,000 |
| loyalty_transaction | 77,000 |
| guest | 50,000 |
| housekeeping_task | 50,000 |
| room / employee / hotel | 600 / 120 / 5 |

Bookings run from January 2023 to January 2027, never overlap on the same room (the Portfolio 1 exclusion constraint is respected), and repeat guests are common. Prices are in USD.

## 5. Query catalogue (`02_queries.sql`)
| # | Business question | Techniques |
|---|---|---|
| Q1 | Which Double rooms are free on given dates? | NOT EXISTS, range overlap `&&` |
| Q2 | Next 15 upcoming confirmed bookings at one hotel | 7-table join |
| Q3 | Revenue per hotel per quarter | Aggregation, `date_trunc` |
| Q4 | Top 3 guests by spend per hotel | CTE, `RANK() OVER (PARTITION BY ...)` |
| Q5 | Monthly occupancy rate per hotel | `generate_series`, range arithmetic |
| Q6 | Monthly revenue, growth and running total | `LAG()`, cumulative `SUM() OVER` |
| Q7 | Cancellation and no-show rate by channel | `FILTER` aggregation |
| Q8 | Guests who stayed at 4+ hotels | `HAVING COUNT(DISTINCT)` |
| Q9 | Largest outstanding balances | LEFT JOIN to aggregate, `CASE` |
| Q10 | Service revenue share per hotel | Window `SUM() OVER (PARTITION BY)` |
| Q11 | Length of stay and daily rate with sub-totals | `ROLLUP`, `GROUPING()` |
| Q12 | Check-in demand by weekday | `EXTRACT`, window percentage |

## 6. Optimisation experiments (`04_optimisation_experiments.sql`)
| # | Problem | Change | What to look for in the plan |
|---|---|---|---|
| E1 | Search guests by last name | B-tree index | Seq Scan becomes Index/Bitmap Scan |
| E2 | Case-insensitive search ignores the index | Expression index on `lower(last_name)` | Plain index unused, expression index used |
| E3 | Report on rare failed payments | Partial index (`WHERE status = 'failed'`) | Much smaller index, fewer buffers read |
| E4 | Revenue by month scans the whole invoice table | Covering index (`INCLUDE`) | Index Only Scan, `Heap Fetches: 0` |
| E5 | Free-room search written three ways | NOT EXISTS vs NOT IN vs LEFT JOIN | All use the GiST index created by the EXCLUDE constraint |
| E6 | Latest booking per guest | Correlated subquery vs `DISTINCT ON` vs window function | Subquery executed once per row (`loops=`) vs one sort |
| E7 | One month of bookings | Partitioning by year vs flat table vs indexed flat table | Partition pruning (only `booking_part_2025` scanned) |
| E8 | Dashboard reads monthly revenue repeatedly | Materialized view | Live aggregation vs reading a few stored rows |

### How to read an execution plan
- **Seq Scan**: reads the whole table. **Index / Bitmap / Index Only Scan**: uses an index.
- `cost=` is the planner's estimate, `actual time=` is what really happened (milliseconds), `rows=` estimated vs actual shows how good the statistics are.
- `loops=` shows how many times a node ran; a large number inside a subplan is a warning sign.
- `Buffers: shared hit/read` shows how many 8 KB pages were read from cache or disk.
- `Execution Time` at the bottom is the figure to compare before and after.

## 7. My measurements 

| Experiment | Before (ms) | After (ms) | Plan change | Speed-up |
|---|---|---|---|---|
| E1 guest Okafor |5.227 | 0.769|idx_guest_last_name| 6.797 |
| E2 lower(okafor) | 13.781| 0.971 | idx_guest_lower_last_name|14.192|
| E3 failed payments | 49.229| 6.184 | idx_payment_failed_paid_at |7.960 |
| E4 covering index |86.332 | 55.934| idx_invoice_issued_cover| 1.543|
| E5a / E5b / E5c | 50.456/40.805/39.678| | booking_room br | |
| E6a / E6b / E6c | 8009.651/613.838/607.845| |booking b | |
| E7a / E7b / E7c |68.923/ 25.445/2.170 | |booking_flat | |
| E8a / E8b |  297.373/0.132| |mv_hotel_monthly_revenue | |

## 8. Performance analysis 
Experiments on The Homes database (about 221,000 bookings and 403,000 payments) showed that the biggest gains came from matching the access method to the query, not from adding indexes everywhere.

The partial index in E3 gave a clear improvement: the query fell from 49.229ms to 6.184ms, replacing a sequential scan of the payment table with an index scan. The index was only 200 kB because it covers just failed payments. E4’s covering index produced an Index Only Scan with no heap fetches, reducing time from 86.332ms to 55.934 ms, at a storage cost of 6.4 MB.

E1 and E2 improved only modestly (0.769 to 0.971ms), because the guest table is small and a sequential scan was already cheap. E2 also showed that a plain index cannot serve lower(last_name); an expression index was required.

Query rewriting mattered more than indexing in E6. The correlated subquery executed once per booking (loops = 220962) and took 0.008 ms, whereas DISTINCT ON and ROW_NUMBER(5.87) took about 8009.651ms. In E5, NOT EXISTS, NOT IN and LEFT JOIN all used the GiST index created by the exclusion constraint, so the formulation made little difference.

In E7, partition pruning scanned only the 2025 partition and beat the unindexed flat table, but a B-tree index on the flat table was [faster/slower still] (0.408 ms against  68.923 ms). At this size, partitioning is mainly a maintenance benefit, such as dropping old years. In E8, the materialized view answered from a few stored rows, but its data is stale until refreshed.

Every index costs storage and slows writes, so indexes should target measured slow queries. Limitations: one machine, simulated data, warm cache, and parallelism disabled.

## 9. Screenshot checklist (save in `screenshots/`)
- [ ] `01-data-loaded.png`: row-count summary at the end of `01_sample_data.sql`
- [ ] `02-query-q01.png`: sample query results
- [ ] `03-e1-before.png` and `03-e1-after.png`: Seq Scan vs index scan
- [ ] `04-e4-index-only-scan.png`: `Heap Fetches: 0`
- [ ] `05-e6-correlated-loops.png`: the `loops=` figure in the correlated subquery
- [ ] `06-e7-partition-pruning.png`: only one partition scanned
- [ ] '09-for Error' :using -0 instead of lower case -o

## 10. Reflection
I was using a zero -0 instead of lower case -o which is a different psql option (it changes the record separator), so the output stayed on screen instead of going to a file. It really took time troubleshoot where the issue is from

## 11. AI-use declaration
I used AI to generate the data for the query analysis 
