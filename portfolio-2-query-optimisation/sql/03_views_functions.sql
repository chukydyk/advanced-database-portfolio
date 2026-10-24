-- =====================================================================
-- Portfolio 2 | 03_views_functions.sql
-- Reusable query objects: two views, one materialized view, one function.
-- Safe to re-run (uses CREATE OR REPLACE / DROP IF EXISTS).
-- =====================================================================
\set ON_ERROR_STOP on

-- A flattened view of bookings for front-desk and reporting use
CREATE OR REPLACE VIEW v_booking_overview AS
SELECT b.booking_id, b.status, b.booked_at, b.check_in_date, b.check_out_date,
       (b.check_out_date - b.check_in_date) AS nights, b.num_guests,
       h.hotel_id, h.name AS hotel, h.city,
       g.guest_id, g.first_name || ' ' || g.last_name AS guest, g.email AS guest_email,
       bs.source_name,
       r.room_id, r.room_number, rt.type_name AS room_type, br.rate_applied
FROM booking b
JOIN hotel h           ON h.hotel_id = b.hotel_id
JOIN guest g           ON g.guest_id = b.guest_id
JOIN booking_source bs ON bs.source_id = b.source_id
JOIN booking_room br   ON br.booking_id = b.booking_id
JOIN room r            ON r.room_id = br.room_id
JOIN room_type rt      ON rt.room_type_id = r.room_type_id;

-- Monthly revenue per hotel computed live from invoices
CREATE OR REPLACE VIEW v_hotel_monthly_revenue AS
SELECT b.hotel_id, date_trunc('month', i.issued_at)::date AS month,
       count(*) AS invoices, sum(i.total_amount) AS revenue
FROM invoice i
JOIN booking b ON b.booking_id = i.booking_id
WHERE i.status IN ('paid', 'partially_paid')
GROUP BY b.hotel_id, date_trunc('month', i.issued_at);

-- The same result stored physically: fast to read, refreshed on demand
DROP MATERIALIZED VIEW IF EXISTS mv_hotel_monthly_revenue;
CREATE MATERIALIZED VIEW mv_hotel_monthly_revenue AS
SELECT * FROM v_hotel_monthly_revenue;
CREATE UNIQUE INDEX uq_mv_hotel_monthly_revenue ON mv_hotel_monthly_revenue (hotel_id, month);
-- Refresh without blocking readers:
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_hotel_monthly_revenue;

-- Availability search as a reusable function
CREATE OR REPLACE FUNCTION fn_available_rooms(
    p_hotel_id  int,
    p_check_in  date,
    p_check_out date,
    p_room_type text DEFAULT NULL)
RETURNS TABLE (room_id int, room_number varchar, floor smallint, room_type varchar, nightly_rate numeric)
LANGUAGE sql STABLE AS $$
    SELECT r.room_id, r.room_number, r.floor, rt.type_name, ra.nightly_rate
    FROM room r
    JOIN room_type rt ON rt.room_type_id = r.room_type_id
    JOIN rate ra      ON ra.hotel_id = r.hotel_id AND ra.room_type_id = r.room_type_id
                     AND p_check_in BETWEEN ra.valid_from AND ra.valid_to
    WHERE r.hotel_id = p_hotel_id
      AND r.status <> 'maintenance'
      AND (p_room_type IS NULL OR rt.type_name = p_room_type)
      AND NOT EXISTS (SELECT 1 FROM booking_room br
                      WHERE br.room_id = r.room_id AND br.is_active
                        AND br.stay_period && daterange(p_check_in, p_check_out, '[)'))
    ORDER BY r.room_number;
$$;

-- Quick demonstrations
-- SELECT * FROM fn_available_rooms(1, '2026-12-20', '2026-12-24');
-- SELECT * FROM fn_available_rooms(2, '2026-12-20', '2026-12-24', 'Suite');
-- SELECT * FROM v_booking_overview WHERE guest_id = 1 ORDER BY check_in_date DESC LIMIT 10;
