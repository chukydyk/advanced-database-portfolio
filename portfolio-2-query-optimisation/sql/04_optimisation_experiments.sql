-- =====================================================================
-- Portfolio 2 | 04_optimisation_experiments.sql
-- Eight before/after experiments. Each one prints the execution plan
-- (EXPLAIN ANALYZE) BEFORE and AFTER the change.
--
-- Run from the portfolio-2-query-optimisation folder:
--   psql -U postgres -d the_homes -f sql/04_optimisation_experiments.sql -o execution-plans/04_experiments_output.txt
--
-- Tips for fair measurements
--   * Run the whole script TWICE and use the numbers from the second run
--     (the first run warms the cache).
--   * Parallel workers and JIT are switched off so plans are easy to read.
--   * Your timings will differ from anyone else's: that is expected.
--     Compare BEFORE with AFTER on your own machine.
-- =====================================================================
\set ON_ERROR_STOP on
\pset pager off
SET max_parallel_workers_per_gather = 0;
SET jit = off;

-- Make every experiment start from the same baseline
DROP INDEX IF EXISTS idx_guest_last_name;
DROP INDEX IF EXISTS idx_guest_lower_last_name;
DROP INDEX IF EXISTS idx_payment_failed_paid_at;
DROP INDEX IF EXISTS idx_invoice_issued_cover;
DROP TABLE IF EXISTS booking_part;
DROP TABLE IF EXISTS booking_flat;
ANALYZE;

-- =====================================================================
\qecho
\qecho ######################################################################
\qecho E1  B-tree index on a frequently searched column (guest last name)
\qecho ######################################################################
\qecho --- E1 BEFORE (no index on last_name) ---
EXPLAIN (ANALYZE, BUFFERS)
SELECT guest_id, first_name, last_name, email FROM guest WHERE last_name = 'Okafor';

CREATE INDEX idx_guest_last_name ON guest (last_name);
ANALYZE guest;

\qecho --- E1 AFTER (idx_guest_last_name) ---
EXPLAIN (ANALYZE, BUFFERS)
SELECT guest_id, first_name, last_name, email FROM guest WHERE last_name = 'Okafor';

-- =====================================================================
\qecho
\qecho ######################################################################
\qecho E2  Expression index: case-insensitive search defeats a plain index
\qecho ######################################################################
\qecho --- E2 BEFORE (lower(last_name) cannot use idx_guest_last_name) ---
EXPLAIN (ANALYZE, BUFFERS)
SELECT guest_id, first_name, last_name FROM guest WHERE lower(last_name) = 'okafor';

CREATE INDEX idx_guest_lower_last_name ON guest (lower(last_name));
ANALYZE guest;

\qecho --- E2 AFTER (idx_guest_lower_last_name) ---
EXPLAIN (ANALYZE, BUFFERS)
SELECT guest_id, first_name, last_name FROM guest WHERE lower(last_name) = 'okafor';

-- =====================================================================
\qecho
\qecho ######################################################################
\qecho E3  Partial index: failed payments are rare, so index only those rows
\qecho ######################################################################
\qecho --- E3 BEFORE ---
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('month', paid_at) AS month, count(*) AS failed_attempts, sum(amount) AS value_at_risk
FROM payment
WHERE status = 'failed' AND paid_at >= DATE '2025-01-01'
GROUP BY 1 ORDER BY 1;

CREATE INDEX idx_payment_failed_paid_at ON payment (paid_at) WHERE status = 'failed';
ANALYZE payment;

\qecho --- E3 AFTER (idx_payment_failed_paid_at) ---
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('month', paid_at) AS month, count(*) AS failed_attempts, sum(amount) AS value_at_risk
FROM payment
WHERE status = 'failed' AND paid_at >= DATE '2025-01-01'
GROUP BY 1 ORDER BY 1;

\qecho --- E3 index sizes: partial index size compared with the table it covers ---
SELECT pg_size_pretty(pg_relation_size('idx_payment_failed_paid_at')) AS partial_index_size,
       pg_size_pretty(pg_relation_size('payment'))                    AS payment_table_size;

-- =====================================================================
\qecho
\qecho ######################################################################
\qecho E4  Covering index (INCLUDE) enabling an index-only scan
\qecho ######################################################################
\qecho --- E4 BEFORE ---
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('month', issued_at) AS month, sum(total_amount) AS revenue
FROM invoice
WHERE issued_at >= DATE '2025-01-01' AND issued_at < DATE '2026-01-01'
GROUP BY 1 ORDER BY 1;

CREATE INDEX idx_invoice_issued_cover ON invoice (issued_at) INCLUDE (total_amount);
VACUUM (ANALYZE) invoice;   -- updates the visibility map so index-only scans work

\qecho --- E4 AFTER (idx_invoice_issued_cover) ---
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('month', issued_at) AS month, sum(total_amount) AS revenue
FROM invoice
WHERE issued_at >= DATE '2025-01-01' AND issued_at < DATE '2026-01-01'
GROUP BY 1 ORDER BY 1;

-- =====================================================================
\qecho
\qecho ######################################################################
\qecho E5  Query rewrite: three ways to ask which rooms are free
\qecho      (the GiST index created by the EXCLUDE constraint serves all three)
\qecho ######################################################################
\qecho --- E5a NOT EXISTS ---
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.room_id, r.room_number
FROM room r
WHERE r.hotel_id = 1
  AND NOT EXISTS (SELECT 1 FROM booking_room br
                  WHERE br.room_id = r.room_id AND br.is_active
                    AND br.stay_period && daterange('2026-12-20', '2026-12-24', '[)'));

\qecho --- E5b NOT IN ---
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.room_id, r.room_number
FROM room r
WHERE r.hotel_id = 1
  AND r.room_id NOT IN (SELECT br.room_id FROM booking_room br
                        WHERE br.is_active
                          AND br.stay_period && daterange('2026-12-20', '2026-12-24', '[)'));

\qecho --- E5c LEFT JOIN ... IS NULL ---
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.room_id, r.room_number
FROM room r
LEFT JOIN booking_room br ON br.room_id = r.room_id AND br.is_active
                         AND br.stay_period && daterange('2026-12-20', '2026-12-24', '[)')
WHERE r.hotel_id = 1 AND br.room_id IS NULL;

-- =====================================================================
\qecho
\qecho ######################################################################
\qecho E6  Query rewrite: correlated subquery vs DISTINCT ON vs window function
\qecho      Task: the most recent booking of each guest (rows counted to keep output short)
\qecho ######################################################################
\qecho --- E6a correlated subquery ---
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM booking b
WHERE b.check_in_date = (SELECT max(b2.check_in_date) FROM booking b2 WHERE b2.guest_id = b.guest_id);

\qecho --- E6b DISTINCT ON ---
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM (SELECT DISTINCT ON (guest_id) booking_id
                      FROM booking ORDER BY guest_id, check_in_date DESC) t;

\qecho --- E6c ROW_NUMBER() window function ---
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM (SELECT booking_id, ROW_NUMBER() OVER (PARTITION BY guest_id ORDER BY check_in_date DESC) AS rn
                      FROM booking) t WHERE rn = 1;

-- =====================================================================
\qecho
\qecho ######################################################################
\qecho E7  Partitioning: a month of bookings from a flat table, a partitioned
\qecho      table, and a flat table with an index (all three hold the same rows)
\qecho ######################################################################
CREATE TABLE booking_flat AS SELECT * FROM booking;

CREATE TABLE booking_part (LIKE booking INCLUDING DEFAULTS) PARTITION BY RANGE (check_in_date);
CREATE TABLE booking_part_2023 PARTITION OF booking_part FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');
CREATE TABLE booking_part_2024 PARTITION OF booking_part FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE booking_part_2025 PARTITION OF booking_part FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
CREATE TABLE booking_part_2026 PARTITION OF booking_part FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
CREATE TABLE booking_part_2027 PARTITION OF booking_part FOR VALUES FROM ('2027-01-01') TO ('2028-01-01');
INSERT INTO booking_part SELECT * FROM booking;
ANALYZE booking_flat;
ANALYZE booking_part;

\qecho --- E7a flat table, no index ---
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(num_guests) FROM booking_flat
WHERE check_in_date >= DATE '2025-06-01' AND check_in_date < DATE '2025-07-01';

\qecho --- E7b partitioned by year (partition pruning) ---
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(num_guests) FROM booking_part
WHERE check_in_date >= DATE '2025-06-01' AND check_in_date < DATE '2025-07-01';

CREATE INDEX idx_booking_flat_checkin ON booking_flat (check_in_date);
ANALYZE booking_flat;

\qecho --- E7c flat table with a B-tree index on check_in_date ---
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(num_guests) FROM booking_flat
WHERE check_in_date >= DATE '2025-06-01' AND check_in_date < DATE '2025-07-01';

-- =====================================================================
\qecho
\qecho ######################################################################
\qecho E8  Pre-computation: live view vs materialized view (monthly revenue)
\qecho      Requires 03_views_functions.sql to have been run first
\qecho ######################################################################
\qecho --- E8a query on the live view v_hotel_monthly_revenue ---
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM v_hotel_monthly_revenue WHERE hotel_id = 1 AND month >= DATE '2025-01-01';

\qecho --- E8b same question on mv_hotel_monthly_revenue ---
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM mv_hotel_monthly_revenue WHERE hotel_id = 1 AND month >= DATE '2025-01-01';

-- =====================================================================
\qecho
\qecho ######################################################################
\qecho Index inventory after the experiments
\qecho ######################################################################
SELECT tablename, indexname, pg_size_pretty(pg_relation_size(quote_ident(indexname)::regclass)) AS size
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN ('idx_guest_last_name', 'idx_guest_lower_last_name', 'idx_payment_failed_paid_at',
                    'idx_invoice_issued_cover', 'idx_booking_flat_checkin')
ORDER BY tablename, indexname;
