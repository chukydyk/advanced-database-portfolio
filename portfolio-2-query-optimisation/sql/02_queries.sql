-- =====================================================================
-- Portfolio 2 | 02_queries.sql
-- Twelve business queries for The Homes hotel chain.
-- Techniques: joins, subqueries, CTEs, window functions, FILTER,
--             ROLLUP, range operators, date arithmetic.
--
-- Run from the portfolio-2-query-optimisation folder and save the output:
--   psql -U postgres -d the_homes -f sql/02_queries.sql -o results/02_queries_output.txt
-- =====================================================================
\pset pager off
\pset null '-'

-- ---------------------------------------------------------------------
\qecho
\qecho ======================================================================
\qecho Q1  Availability search: free Double rooms at The Homes Abuja
\qecho     for 20 to 24 Dec 2026 (check-out day is free: half-open range)
\qecho Technique: NOT EXISTS anti-join + range overlap operator (&&)
\qecho ======================================================================
SELECT r.room_id, r.room_number, r.floor, rt.type_name
FROM room r
JOIN room_type rt ON rt.room_type_id = r.room_type_id
WHERE r.hotel_id = 1
  AND rt.type_name = 'Standard Double'
  AND r.status <> 'maintenance'
  AND NOT EXISTS (SELECT 1
                  FROM booking_room br
                  WHERE br.room_id = r.room_id
                    AND br.is_active
                    AND br.stay_period && daterange('2026-12-20', '2026-12-24', '[)'))
ORDER BY r.room_number;

-- ---------------------------------------------------------------------
\qecho
\qecho ======================================================================
\qecho Q2  The next 15 upcoming confirmed bookings at The Homes Lagos
\qecho Technique: seven-table join
\qecho ======================================================================
SELECT b.booking_id,
       g.first_name || ' ' || g.last_name AS guest,
       h.name AS hotel,
       r.room_number, rt.type_name,
       b.check_in_date, b.check_out_date,
       (b.check_out_date - b.check_in_date) AS nights,
       bs.source_name, br.rate_applied
FROM booking b
JOIN guest g           ON g.guest_id = b.guest_id
JOIN hotel h           ON h.hotel_id = b.hotel_id
JOIN booking_source bs ON bs.source_id = b.source_id
JOIN booking_room br   ON br.booking_id = b.booking_id
JOIN room r            ON r.room_id = br.room_id
JOIN room_type rt      ON rt.room_type_id = r.room_type_id
WHERE b.hotel_id = 2 AND b.status = 'confirmed' AND b.check_in_date >= current_date
ORDER BY b.check_in_date, b.booking_id
LIMIT 15;

-- ---------------------------------------------------------------------
\qecho
\qecho ======================================================================
\qecho Q3  Revenue per hotel per quarter, 2025 (paid and partly paid invoices)
\qecho Technique: aggregation, date_trunc, joins
\qecho ======================================================================
SELECT h.name AS hotel,
       to_char(date_trunc('quarter', i.issued_at), 'YYYY "Q"Q') AS quarter,
       count(*)                      AS invoices,
       round(sum(i.total_amount), 2) AS revenue
FROM invoice i
JOIN booking b ON b.booking_id = i.booking_id
JOIN hotel h   ON h.hotel_id = b.hotel_id
WHERE i.status IN ('paid', 'partially_paid')
  AND i.issued_at >= DATE '2025-01-01' AND i.issued_at < DATE '2026-01-01'
GROUP BY h.name, date_trunc('quarter', i.issued_at)
ORDER BY h.name, quarter;

-- ---------------------------------------------------------------------
\qecho
\qecho ======================================================================
\qecho Q4  Top 3 guests by total spend at each hotel (all time)
\qecho Technique: CTE + RANK() window function partitioned by hotel
\qecho ======================================================================
WITH spend AS (
    SELECT b.hotel_id, b.guest_id, sum(i.total_amount) AS total_spend, count(*) AS stays
    FROM invoice i
    JOIN booking b ON b.booking_id = i.booking_id
    WHERE i.status = 'paid'
    GROUP BY b.hotel_id, b.guest_id
), ranked AS (
    SELECT s.*, RANK() OVER (PARTITION BY s.hotel_id ORDER BY s.total_spend DESC) AS rnk
    FROM spend s
)
SELECT h.name AS hotel, r.rnk, g.first_name || ' ' || g.last_name AS guest,
       r.stays, round(r.total_spend, 2) AS total_spend
FROM ranked r
JOIN hotel h ON h.hotel_id = r.hotel_id
JOIN guest g ON g.guest_id = r.guest_id
WHERE r.rnk <= 3
ORDER BY h.name, r.rnk;

-- ---------------------------------------------------------------------
\qecho
\qecho ======================================================================
\qecho Q5  Monthly occupancy rate per hotel, 2025
\qecho Technique: generate_series calendar, range arithmetic, nested CTEs
\qecho ======================================================================
WITH months AS (
    SELECT m::date AS month_start, (m + INTERVAL '1 month')::date AS month_end
    FROM generate_series(DATE '2025-01-01', DATE '2025-12-01', INTERVAL '1 month') m
), cap AS (
    SELECT hotel_id, count(*) AS rooms FROM room GROUP BY hotel_id
), occ AS (
    SELECT r.hotel_id, mo.month_start, mo.month_end,
           sum(least(upper(br.stay_period), mo.month_end)
             - greatest(lower(br.stay_period), mo.month_start)) AS room_nights
    FROM months mo
    JOIN booking_room br ON br.is_active
                        AND br.stay_period && daterange(mo.month_start, mo.month_end, '[)')
    JOIN room r ON r.room_id = br.room_id
    GROUP BY r.hotel_id, mo.month_start, mo.month_end
)
SELECT h.name AS hotel,
       to_char(o.month_start, 'YYYY-MM') AS month,
       o.room_nights,
       round(100.0 * o.room_nights / (c.rooms * (o.month_end - o.month_start)), 1) AS occupancy_pct
FROM occ o
JOIN cap c   ON c.hotel_id = o.hotel_id
JOIN hotel h ON h.hotel_id = o.hotel_id
ORDER BY h.name, o.month_start;

-- ---------------------------------------------------------------------
\qecho
\qecho ======================================================================
\qecho Q6  Chain-wide monthly revenue with month-on-month growth and running total
\qecho Technique: LAG() and cumulative SUM() window functions
\qecho ======================================================================
WITH monthly AS (
    SELECT date_trunc('month', issued_at)::date AS month, sum(total_amount) AS revenue
    FROM invoice
    WHERE status IN ('paid', 'partially_paid')
      AND issued_at >= DATE '2025-01-01' AND issued_at < DATE '2026-01-01'
    GROUP BY 1
)
SELECT to_char(month, 'YYYY-MM') AS month,
       round(revenue, 2) AS revenue,
       round(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
             / NULLIF(LAG(revenue) OVER (ORDER BY month), 0), 1) AS growth_pct,
       round(sum(revenue) OVER (ORDER BY month), 2) AS running_total
FROM monthly
ORDER BY month;

-- ---------------------------------------------------------------------
\qecho
\qecho ======================================================================
\qecho Q7  Cancellation and no-show rate by booking channel
\qecho Technique: conditional aggregation with FILTER
\qecho ======================================================================
SELECT bs.source_name,
       count(*) AS bookings,
       count(*) FILTER (WHERE b.status = 'cancelled') AS cancelled,
       count(*) FILTER (WHERE b.status = 'no_show')   AS no_shows,
       round(100.0 * count(*) FILTER (WHERE b.status = 'cancelled') / count(*), 2) AS cancel_pct,
       round(100.0 * count(*) FILTER (WHERE b.status = 'no_show')   / count(*), 2) AS no_show_pct
FROM booking b
JOIN booking_source bs ON bs.source_id = b.source_id
GROUP BY bs.source_name
ORDER BY cancel_pct DESC;

-- ---------------------------------------------------------------------
\qecho
\qecho ======================================================================
\qecho Q8  Guests who have stayed (completed) at four or more different hotels
\qecho Technique: GROUP BY ... HAVING with COUNT(DISTINCT), subquery in FROM
\qecho ======================================================================
SELECT g.guest_id, g.first_name || ' ' || g.last_name AS guest, g.nationality,
       t.hotels_visited, t.completed_stays
FROM (SELECT guest_id, count(DISTINCT hotel_id) AS hotels_visited, count(*) AS completed_stays
      FROM booking
      WHERE status = 'completed'
      GROUP BY guest_id
      HAVING count(DISTINCT hotel_id) >= 4) t
JOIN guest g ON g.guest_id = t.guest_id
ORDER BY t.completed_stays DESC, g.guest_id
LIMIT 15;

-- ---------------------------------------------------------------------
\qecho
\qecho ======================================================================
\qecho Q9  Largest outstanding balances on completed stays
\qecho Technique: LEFT JOIN to an aggregated derived table, FILTER, CASE
\qecho ======================================================================
SELECT i.invoice_id, b.booking_id,
       g.first_name || ' ' || g.last_name AS guest,
       h.name AS hotel,
       i.total_amount,
       coalesce(p.net_paid, 0) AS net_paid,
       round(i.total_amount - coalesce(p.net_paid, 0), 2) AS balance_due
FROM invoice i
JOIN booking b ON b.booking_id = i.booking_id
JOIN guest g   ON g.guest_id = b.guest_id
JOIN hotel h   ON h.hotel_id = b.hotel_id
LEFT JOIN (SELECT invoice_id,
                  sum(CASE WHEN payment_type = 'refund' THEN -amount ELSE amount END)
                      FILTER (WHERE status = 'successful') AS net_paid
           FROM payment GROUP BY invoice_id) p ON p.invoice_id = i.invoice_id
WHERE b.status = 'completed'
  AND i.total_amount - coalesce(p.net_paid, 0) > 0.01
ORDER BY balance_due DESC
LIMIT 15;

-- ---------------------------------------------------------------------
\qecho
\qecho ======================================================================
\qecho Q10 Ancillary service revenue by hotel with share of the hotel total
\qecho Technique: aggregation + SUM() OVER (PARTITION BY ...) window
\qecho ======================================================================
SELECT h.name AS hotel, s.service_name,
       sum(so.quantity) AS units_sold,
       round(sum(so.quantity * so.unit_price_charged), 2) AS revenue,
       round(100.0 * sum(so.quantity * so.unit_price_charged)
             / sum(sum(so.quantity * so.unit_price_charged)) OVER (PARTITION BY h.hotel_id), 1) AS pct_of_hotel
FROM service_order so
JOIN service s ON s.service_id = so.service_id
JOIN hotel h   ON h.hotel_id = s.hotel_id
GROUP BY h.hotel_id, h.name, s.service_name
ORDER BY h.name, revenue DESC;

-- ---------------------------------------------------------------------
\qecho
\qecho ======================================================================
\qecho Q11 Average length of stay and average daily rate by hotel and room type,
\qecho     with sub-totals per hotel and a chain-wide grand total
\qecho Technique: GROUP BY ROLLUP, GROUPING()
\qecho ======================================================================
SELECT CASE WHEN GROUPING(h.name) = 1 THEN 'ALL HOTELS' ELSE h.name END AS hotel,
       CASE WHEN GROUPING(rt.type_name) = 1 THEN 'all room types' ELSE rt.type_name END AS room_type,
       count(*) AS completed_stays,
       round(avg(b.check_out_date - b.check_in_date), 2) AS avg_nights,
       round(avg(br.rate_applied), 2) AS avg_daily_rate
FROM booking b
JOIN booking_room br ON br.booking_id = b.booking_id
JOIN room r          ON r.room_id = br.room_id
JOIN room_type rt    ON rt.room_type_id = r.room_type_id
JOIN hotel h         ON h.hotel_id = b.hotel_id
WHERE b.status = 'completed'
GROUP BY ROLLUP (h.name, rt.type_name)
ORDER BY GROUPING(h.name), h.name, GROUPING(rt.type_name), rt.type_name;

-- ---------------------------------------------------------------------
\qecho
\qecho ======================================================================
\qecho Q12 Check-in demand by day of week (staffing insight)
\qecho Technique: EXTRACT, window SUM for percentage share
\qecho ======================================================================
SELECT to_char(check_in_date, 'Dy') AS weekday,
       EXTRACT(isodow FROM check_in_date)::int AS dow_no,
       count(*) AS check_ins,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct_of_total
FROM booking
WHERE status IN ('completed', 'checked_in')
GROUP BY 1, 2
ORDER BY dow_no;
