-- =====================================================================
-- Portfolio 2 | 01_sample_data.sql
-- Generates realistic, repeatable sample data for The Homes hotel chain.
--
-- Run ONCE on a freshly created database that already contains the
-- Portfolio 1 schema (schema.sql). To start again, drop and recreate the
-- database and re-run schema.sql first.
--
-- Approximate result: 5 hotels, 600 rooms, 50,000 guests, 220,000 bookings,
-- 400,000+ payments, 85,000+ service orders, 100,000 audit rows.
-- Expected run time: 1 to 4 minutes depending on your machine.
-- =====================================================================
\set ON_ERROR_STOP on
\timing on

SELECT setseed(0.42);   -- fixed seed: everyone gets the same data

-- ---------------------------------------------------------------------
-- Helper functions (temporary: they disappear when the session ends)
-- ---------------------------------------------------------------------
CREATE FUNCTION pg_temp.rnd_first() RETURNS text LANGUAGE sql VOLATILE AS $$
  SELECT a[1 + floor(random() * cardinality(a))::int] FROM (SELECT ARRAY[
   'Chukwuma','Ngozi','Emeka','Amina','Tunde','Bola','Ifeoma','Musa','Fatima','Chidi',
   'Adaeze','Seun','Kemi','Yusuf','Zainab','Obinna','Funke','Ibrahim','Halima','Kofi',
   'Ama','Kwame','Akosua','Yaw','Efua','Wanjiru','Kamau','Achieng','Otieno','Njeri',
   'Sarah','John','Maria','David','Fatou','Pierre','Aisha','Daniel','Grace','Peter'] AS a) t
$$;

CREATE FUNCTION pg_temp.rnd_last() RETURNS text LANGUAGE sql VOLATILE AS $$
  SELECT a[1 + floor(random() * cardinality(a))::int] FROM (SELECT ARRAY[
   'Okafor','Adeyemi','Bello','Eze','Ibrahim','Okonkwo','Balogun','Abubakar','Nwosu','Adebayo',
   'Mensah','Owusu','Boateng','Asante','Kamau','Otieno','Wanjiku','Odhiambo','Smith','Johnson',
   'Williams','Brown','Garcia','Martin','Dupont','Hassan','Danjuma','Chukwu','Obi','Uche',
   'Lawal','Yakubu','Osei','Addo','Mwangi','Njoroge','Akinola','Onyeka','Ogunleye','Usman'] AS a) t
$$;

CREATE FUNCTION pg_temp.rnd_nationality() RETURNS text LANGUAGE sql VOLATILE AS $$
  SELECT a[1 + floor(random() * cardinality(a))::int] FROM (SELECT ARRAY[
   'Nigerian','Nigerian','Nigerian','Nigerian','Nigerian','Nigerian','Ghanaian','Ghanaian',
   'Kenyan','Kenyan','British','American','South African','Cameroonian','Indian','Chinese','German'] AS a) t
$$;

-- ---------------------------------------------------------------------
-- 1. Reference data
-- ---------------------------------------------------------------------
INSERT INTO hotel(name, city, country, address, phone, email, star_rating) VALUES
 ('The Homes Abuja',         'Abuja',         'Nigeria', '12 Ahmadu Bello Way, Maitama',      '+234 9 000 0001',  'abuja@thehomes.example',        5),
 ('The Homes Lagos',         'Lagos',         'Nigeria', '14 Adetokunbo Ademola St, V.I.',    '+234 1 000 0002',  'lagos@thehomes.example',        5),
 ('The Homes Port Harcourt', 'Port Harcourt', 'Nigeria', '8 Aba Road, GRA',                   '+234 84 000 003',  'portharcourt@thehomes.example', 4),
 ('The Homes Accra',         'Accra',         'Ghana',   '22 Independence Avenue, Ridge',     '+233 30 000 0004', 'accra@thehomes.example',        4),
 ('The Homes Nairobi',       'Nairobi',       'Kenya',   '5 Kimathi Street, CBD',             '+254 20 000 0005', 'nairobi@thehomes.example',      4);

INSERT INTO room_type(type_name, max_occupancy, description) VALUES
 ('Standard Single', 1, 'Single bed, work desk'),
 ('Standard Double', 2, 'Queen bed, city view'),
 ('Twin',            2, 'Two single beds'),
 ('Deluxe',          3, 'King bed, sofa, balcony'),
 ('Suite',           4, 'Separate living room, kitchenette');

INSERT INTO amenity(amenity_name) VALUES
 ('WiFi'),('Air conditioning'),('TV'),('Minibar'),('Safe'),('Balcony'),('Kitchenette'),('Bathtub');

INSERT INTO room_type_amenity(room_type_id, amenity_id)
SELECT rt.room_type_id, a.amenity_id
FROM room_type rt
JOIN amenity a ON a.amenity_id <= CASE rt.type_name
        WHEN 'Standard Single' THEN 3 WHEN 'Standard Double' THEN 4 WHEN 'Twin' THEN 4
        WHEN 'Deluxe' THEN 6 ELSE 8 END;

INSERT INTO staff_role(role_name) VALUES
 ('Manager'),('Receptionist'),('Housekeeper'),('Maintenance Technician'),('Concierge');

INSERT INTO booking_source(source_name, commission_rate) VALUES
 ('Website',0),('Mobile App',0),('Walk-in',0),('Travel Agent',15),('Phone',0),('Corporate',5);

INSERT INTO payment_method(method_name) VALUES ('Card'),('Cash'),('Bank Transfer'),('Mobile Money');

INSERT INTO promotion(promo_code, discount_pct, valid_from, valid_to) VALUES
 ('WELCOME10',10,'2023-01-01','2027-12-31'),('FESTIVE15',15,'2023-01-01','2027-12-31'),
 ('WEEKEND5',5,'2023-01-01','2027-12-31'),('LOYAL12',12,'2023-01-01','2027-12-31'),
 ('EARLYBIRD8',8,'2023-01-01','2027-12-31'),('CORP7',7,'2023-01-01','2027-12-31'),
 ('STAYMORE10',10,'2023-01-01','2027-12-31'),('FLASH20',20,'2023-01-01','2027-12-31'),
 ('FAMILY6',6,'2023-01-01','2027-12-31'),('APP5',5,'2023-01-01','2027-12-31');

-- Seasonal rates: 4 periods per year, 2023 to 2027, for every hotel and room type
INSERT INTO rate(hotel_id, room_type_id, season_name, valid_from, valid_to, nightly_rate)
SELECT h.hotel_id, rt.room_type_id, s.season,
       make_date(y.y, s.m1, s.d1), make_date(y.y, s.m2, s.d2),
       round((ARRAY[60,80,85,130,250])[rt.room_type_id] * (0.95 + (h.hotel_id % 4) * 0.05) * s.mult, 2)
FROM hotel h
CROSS JOIN room_type rt
CROSS JOIN generate_series(2023, 2027) y(y)
CROSS JOIN (VALUES ('Peak (New Year)',1,1,1,5,1.40),
                   ('Low',            1,6,4,30,0.80),
                   ('Regular',        5,1,12,14,1.00),
                   ('Peak (Festive)', 12,15,12,31,1.40)) s(season,m1,d1,m2,d2,mult);

INSERT INTO service(hotel_id, service_name, unit_price)
SELECT h.hotel_id, s.name, round(s.price * (0.95 + (h.hotel_id % 4) * 0.05), 2)
FROM hotel h
CROSS JOIN (VALUES ('Restaurant',25),('Room Service',20),('Spa',60),
                   ('Laundry',12),('Airport Pickup',35),('Minibar',15)) s(name, price);

-- 120 rooms per hotel (8 floors x 15 rooms)
INSERT INTO room(hotel_id, room_type_id, room_number, floor)
SELECT h.hotel_id, rt.room_type_id,
       ((1 + (k - 1) / 15) * 100 + ((k - 1) % 15) + 1)::text,
       (1 + (k - 1) / 15)::smallint
FROM hotel h
CROSS JOIN generate_series(1, 120) k
JOIN room_type rt ON rt.type_name = CASE WHEN k <= 30 THEN 'Standard Single'
                                         WHEN k <= 60 THEN 'Standard Double'
                                         WHEN k <= 80 THEN 'Twin'
                                         WHEN k <= 105 THEN 'Deluxe'
                                         ELSE 'Suite' END;

-- 24 staff per hotel
INSERT INTO employee(hotel_id, role_id, first_name, last_name, email, hire_date)
SELECT x.hotel_id, sr.role_id, pg_temp.rnd_first(), pg_temp.rnd_last(),
       'staff' || x.hotel_id || '.' || x.p || '@thehomes.example',
       DATE '2019-01-01' + floor(random() * 2000)::int
FROM (SELECT h.hotel_id, p,
             CASE WHEN p = 1 THEN 'Manager' WHEN p <= 7 THEN 'Receptionist'
                  WHEN p <= 17 THEN 'Housekeeper' WHEN p <= 20 THEN 'Maintenance Technician'
                  ELSE 'Concierge' END AS rn
      FROM hotel h CROSS JOIN generate_series(1, 24) p) x
JOIN staff_role sr ON sr.role_name = x.rn;

-- ---------------------------------------------------------------------
-- 2. Guests (50,000)
-- ---------------------------------------------------------------------
INSERT INTO guest(first_name, last_name, email, phone, nationality, id_type, id_doc_ref, registered_at)
SELECT q.fn, q.ln,
       lower(q.fn) || '.' || lower(q.ln) || '.' || q.n || '@example.com',
       '+' || (234000000000 + floor(random() * 999999999))::bigint,
       pg_temp.rnd_nationality(),
       (ARRAY['Passport','National ID','Driver Licence'])[1 + floor(random() * 3)::int],
       'ID-****' || lpad(floor(random() * 10000)::int::text, 4, '0'),
       TIMESTAMP '2022-06-01' + random() * (TIMESTAMP '2026-10-01' - TIMESTAMP '2022-06-01')
FROM (SELECT n, pg_temp.rnd_first() AS fn, pg_temp.rnd_last() AS ln
      FROM generate_series(1, 50000) n) q;

-- ---------------------------------------------------------------------
-- 3. Bookings: every room gets a chain of back-to-back, NON-OVERLAPPING
--    stays, so the exclusion constraint from Portfolio 1 is respected.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE stg_stay AS
WITH base AS MATERIALIZED (
    SELECT r.room_id, r.hotel_id, rt.max_occupancy, g.n,
           (1 + floor(random() * 5))::int AS nights,       -- 1 to 5 nights
           floor(random() * 3)::int       AS gap           -- 0 to 2 empty nights
    FROM room r
    JOIN room_type rt ON rt.room_type_id = r.room_type_id
    CROSS JOIN generate_series(1, 370) g(n)
), cum AS MATERIALIZED (
    SELECT *, coalesce(sum(nights + gap) OVER (PARTITION BY room_id ORDER BY n
                         ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS off
    FROM base
)
SELECT row_number() OVER (ORDER BY room_id, n)::int AS booking_id,
       room_id, hotel_id, max_occupancy,
       (DATE '2023-01-01' + (off + room_id % 4)::int)            AS check_in_date,
       (DATE '2023-01-01' + (off + room_id % 4 + nights)::int)   AS check_out_date
FROM cum;

DELETE FROM stg_stay WHERE check_in_date > DATE '2027-01-31';

CREATE TEMP TABLE stg_booking AS
WITH r AS MATERIALIZED (
    SELECT s.*,
           random() AS u_source, random() AS u_status, random() AS u_book,
           random() AS u_time,   random() AS u_promo,  random() AS u_promo_id,
           random() AS u_guests, random() AS u_guest
    FROM stg_stay s
)
SELECT booking_id, room_id, hotel_id, check_in_date, check_out_date,
       1 + floor(50000 * power(u_guest, 1.3))::int AS guest_id,            -- skewed: some guests return often
       CASE WHEN u_source < 0.35 THEN 1 WHEN u_source < 0.55 THEN 2 WHEN u_source < 0.65 THEN 3
            WHEN u_source < 0.85 THEN 4 WHEN u_source < 0.95 THEN 5 ELSE 6 END AS source_id,
       CASE WHEN u_promo < 0.15 THEN 1 + floor(u_promo_id * 10)::int END AS promo_id,
       (check_in_date - (1 + floor(u_book * 60))::int)::timestamp + TIME '09:00' + u_time * INTERVAL '10 hours' AS booked_at,
       (1 + floor(u_guests * max_occupancy))::int AS num_guests,
       CASE WHEN check_out_date <= current_date THEN
                 CASE WHEN u_status < 0.06 THEN 'cancelled' WHEN u_status < 0.08 THEN 'no_show' ELSE 'completed' END
            WHEN check_in_date <= current_date THEN 'checked_in'
            ELSE CASE WHEN u_status < 0.15 THEN 'pending' WHEN u_status < 0.22 THEN 'cancelled' ELSE 'confirmed' END
       END AS status
FROM r;

INSERT INTO booking(booking_id, guest_id, hotel_id, source_id, promo_id, booked_at,
                    check_in_date, check_out_date, num_guests, status)
SELECT booking_id, guest_id, hotel_id, source_id, promo_id, booked_at,
       check_in_date, check_out_date, num_guests, status
FROM stg_booking;

SELECT setval(pg_get_serial_sequence('booking', 'booking_id'), (SELECT max(booking_id) FROM booking));

INSERT INTO booking_room(booking_id, room_id, rate_applied, stay_period, is_active)
SELECT b.booking_id, b.room_id,
       round(rt.nightly_rate * (1 - coalesce(p.discount_pct, 0) / 100.0), 2),
       daterange(b.check_in_date, b.check_out_date, '[)'),
       b.status NOT IN ('cancelled', 'no_show')
FROM stg_booking b
JOIN room r  ON r.room_id = b.room_id
JOIN rate rt ON rt.hotel_id = b.hotel_id AND rt.room_type_id = r.room_type_id
            AND b.check_in_date BETWEEN rt.valid_from AND rt.valid_to
LEFT JOIN promotion p ON p.promo_id = b.promo_id;

-- ---------------------------------------------------------------------
-- 4. Services, invoices and payments
-- ---------------------------------------------------------------------
CREATE TEMP TABLE svc AS
SELECT service_id, hotel_id, row_number() OVER (PARTITION BY hotel_id ORDER BY service_id) - 1 AS pos
FROM service;

INSERT INTO service_order(booking_id, service_id, quantity, unit_price_charged, ordered_at)
SELECT q.booking_id, s.service_id, q.qty, sv.unit_price,
       q.check_in_date::timestamp + q.u * (q.check_out_date - q.check_in_date) * INTERVAL '1 day'
FROM (SELECT b.booking_id, b.hotel_id, b.check_in_date, b.check_out_date,
             floor(random() * 6)::int AS pos, 1 + floor(random() * 3)::int AS qty, random() AS u
      FROM booking b
      CROSS JOIN LATERAL generate_series(1, 1 + floor(random() * 3)::int) k
      WHERE b.status IN ('completed', 'checked_in') AND random() < 0.45) q
JOIN svc s      ON s.hotel_id = q.hotel_id AND s.pos = q.pos
JOIN service sv ON sv.service_id = s.service_id;

-- Invoices for completed, in-house and confirmed bookings
INSERT INTO invoice(booking_id, issued_at, subtotal, tax_amount, total_amount, status)
SELECT b.booking_id,
       CASE WHEN b.status = 'completed' THEN b.check_out_date::timestamp + INTERVAL '11 hours' ELSE b.booked_at END,
       x.sub, round(x.sub * 0.075, 2), x.sub + round(x.sub * 0.075, 2),
       CASE WHEN b.status = 'completed' AND random() > 0.05 THEN 'paid' ELSE 'partially_paid' END
FROM booking b
JOIN LATERAL (
     SELECT br.rate_applied * (b.check_out_date - b.check_in_date)
            + coalesce((SELECT sum(so.quantity * so.unit_price_charged)
                        FROM service_order so WHERE so.booking_id = b.booking_id), 0) AS sub
     FROM booking_room br WHERE br.booking_id = b.booking_id) x ON true
WHERE b.status IN ('completed', 'checked_in', 'confirmed');

-- Some cancelled bookings: first-night invoice, deposit taken, then refunded
INSERT INTO invoice(booking_id, issued_at, subtotal, tax_amount, total_amount, status)
SELECT b.booking_id, b.booked_at, x.sub, round(x.sub * 0.075, 2), x.sub + round(x.sub * 0.075, 2), 'refunded'
FROM booking b
JOIN LATERAL (SELECT br.rate_applied AS sub FROM booking_room br WHERE br.booking_id = b.booking_id) x ON true
WHERE b.status = 'cancelled' AND random() < 0.40;

-- Successful deposits (30%) on every invoice
INSERT INTO payment(invoice_id, method_id, payment_type, amount, status, gateway_token, paid_at)
SELECT q.invoice_id,
       CASE WHEN q.u < 0.50 THEN 1 WHEN q.u < 0.70 THEN 3 WHEN q.u < 0.90 THEN 4 ELSE 2 END,
       'deposit', round(q.total_amount * 0.30, 2), 'successful',
       'tok_' || md5(q.invoice_id::text || 'dep'), q.booked_at + INTERVAL '10 minutes'
FROM (SELECT i.invoice_id, i.total_amount, b.booked_at, random() AS u
      FROM invoice i JOIN booking b ON b.booking_id = i.booking_id) q;

-- Failed first attempts (about 4% of invoices) recorded just before the successful deposit
INSERT INTO payment(invoice_id, method_id, payment_type, amount, status, gateway_token, paid_at)
SELECT q.invoice_id, 1, 'deposit', round(q.total_amount * 0.30, 2), 'failed',
       'tok_' || md5(q.invoice_id::text || 'fail'), q.booked_at + INTERVAL '5 minutes'
FROM (SELECT i.invoice_id, i.total_amount, b.booked_at
      FROM invoice i JOIN booking b ON b.booking_id = i.booking_id
      WHERE random() < 0.04) q;

-- Balance paid at check-out for fully paid invoices
INSERT INTO payment(invoice_id, method_id, payment_type, amount, status, gateway_token, paid_at)
SELECT q.invoice_id,
       CASE WHEN q.u < 0.50 THEN 1 WHEN q.u < 0.70 THEN 3 WHEN q.u < 0.90 THEN 4 ELSE 2 END,
       'full', q.total_amount - round(q.total_amount * 0.30, 2), 'successful',
       'tok_' || md5(q.invoice_id::text || 'full'), q.check_out_date::timestamp + INTERVAL '11 hours 30 minutes'
FROM (SELECT i.invoice_id, i.total_amount, b.check_out_date, random() AS u
      FROM invoice i JOIN booking b ON b.booking_id = i.booking_id
      WHERE i.status = 'paid') q;

-- Refunds for cancelled bookings
INSERT INTO payment(invoice_id, method_id, payment_type, amount, status, gateway_token, paid_at)
SELECT i.invoice_id, 1, 'refund', round(i.total_amount * 0.30, 2), 'successful',
       'tok_' || md5(i.invoice_id::text || 'ref'), b.booked_at + INTERVAL '2 days'
FROM invoice i JOIN booking b ON b.booking_id = i.booking_id
WHERE i.status = 'refunded';

-- ---------------------------------------------------------------------
-- 5. Check-in / check-out records, housekeeping, maintenance
-- ---------------------------------------------------------------------
CREATE TEMP TABLE recep AS
SELECT e.hotel_id, array_agg(e.employee_id ORDER BY e.employee_id) AS ids
FROM employee e JOIN staff_role r ON r.role_id = e.role_id
WHERE r.role_name = 'Receptionist' GROUP BY e.hotel_id;

CREATE TEMP TABLE hk AS
SELECT e.hotel_id, array_agg(e.employee_id ORDER BY e.employee_id) AS ids
FROM employee e JOIN staff_role r ON r.role_id = e.role_id
WHERE r.role_name = 'Housekeeper' GROUP BY e.hotel_id;

CREATE TEMP TABLE staff_all AS
SELECT hotel_id, array_agg(employee_id ORDER BY employee_id) AS ids FROM employee GROUP BY hotel_id;

INSERT INTO stay_record(booking_room_id, checked_in_at, checked_out_at, checkin_by, checkout_by)
SELECT q.booking_room_id,
       q.check_in_date::timestamp + INTERVAL '14 hours' + q.u3 * INTERVAL '4 hours',
       CASE WHEN q.status = 'completed'
            THEN q.check_out_date::timestamp + INTERVAL '8 hours' + q.u4 * INTERVAL '4 hours' END,
       rc.ids[1 + floor(q.u1 * cardinality(rc.ids))::int],
       CASE WHEN q.status = 'completed' THEN rc.ids[1 + floor(q.u2 * cardinality(rc.ids))::int] END
FROM (SELECT br.booking_room_id, b.hotel_id, b.status, b.check_in_date, b.check_out_date,
             random() AS u1, random() AS u2, random() AS u3, random() AS u4
      FROM booking_room br JOIN booking b ON b.booking_id = br.booking_id
      WHERE b.status IN ('completed', 'checked_in')) q
JOIN recep rc ON rc.hotel_id = q.hotel_id;

-- Checkout cleans for the last 12 months of completed stays
INSERT INTO housekeeping_task(room_id, assigned_to, task_type, status, created_at, completed_at)
SELECT q.room_id, h.ids[1 + floor(q.u * cardinality(h.ids))::int], 'checkout_clean', 'done',
       q.check_out_date::timestamp + INTERVAL '11 hours',
       q.check_out_date::timestamp + INTERVAL '12 hours' + q.u * INTERVAL '2 hours'
FROM (SELECT br.room_id, b.hotel_id, b.check_out_date, random() AS u
      FROM booking b JOIN booking_room br ON br.booking_id = b.booking_id
      WHERE b.status = 'completed' AND b.check_out_date >= current_date - 365) q
JOIN hk h ON h.hotel_id = q.hotel_id;

INSERT INTO maintenance_request(room_id, reported_by, issue, status, reported_at, resolved_at)
SELECT q.room_id, sa.ids[1 + floor(q.u1 * cardinality(sa.ids))::int], q.issue,
       CASE WHEN q.u2 < 0.97 THEN 'resolved' ELSE 'open' END, q.rep,
       CASE WHEN q.u2 < 0.97 THEN q.rep + (1 + q.u3 * 71) * INTERVAL '1 hour' END
FROM (SELECT r.room_id, r.hotel_id,
             (ARRAY['Air conditioner not cooling','Leaking tap','TV remote faulty','Door lock jammed',
                    'Light fitting broken','Shower pressure low','WiFi router fault'])[1 + floor(random() * 7)::int] AS issue,
             random() AS u1, random() AS u2, random() AS u3,
             TIMESTAMP '2024-10-01' + random() * (current_date - DATE '2024-10-01') * INTERVAL '1 day' AS rep
      FROM room r CROSS JOIN generate_series(1, 5) k WHERE random() < 0.85) q
JOIN staff_all sa ON sa.hotel_id = q.hotel_id;

-- Room status reflects today's situation
UPDATE room SET status = 'occupied'
WHERE room_id IN (SELECT room_id FROM booking_room WHERE is_active AND stay_period @> current_date);
UPDATE room SET status = 'cleaning'
WHERE status = 'available'
  AND room_id IN (SELECT room_id FROM booking_room WHERE is_active AND upper(stay_period) = current_date);
UPDATE room SET status = 'maintenance'
WHERE status = 'available'
  AND room_id IN (SELECT room_id FROM maintenance_request WHERE status = 'open');

-- ---------------------------------------------------------------------
-- 6. Loyalty programme (40% of guests are members)
-- ---------------------------------------------------------------------
INSERT INTO loyalty_account(guest_id) SELECT guest_id FROM guest WHERE guest_id % 5 IN (0, 1);

INSERT INTO loyalty_transaction(loyalty_id, points_change, reason, created_at)
SELECT la.loyalty_id, (b.check_out_date - b.check_in_date) * 100, 'Stay points',
       b.check_out_date::timestamp + INTERVAL '12 hours'
FROM booking b JOIN loyalty_account la ON la.guest_id = b.guest_id
WHERE b.status = 'completed';

UPDATE loyalty_account la
SET points_balance = t.s,
    tier = CASE WHEN t.s >= 20000 THEN 'Platinum' WHEN t.s >= 10000 THEN 'Gold'
                WHEN t.s >= 4000 THEN 'Silver' ELSE 'Standard' END
FROM (SELECT loyalty_id, sum(points_change)::int AS s FROM loyalty_transaction GROUP BY loyalty_id) t
WHERE t.loyalty_id = la.loyalty_id;

-- ---------------------------------------------------------------------
-- 7. Audit log (booking status changes)
-- ---------------------------------------------------------------------
INSERT INTO audit_log(table_name, record_id, action, changed_by, changed_at, old_data, new_data)
SELECT 'booking', b.booking_id, 'UPDATE', 1 + floor(random() * 120)::int,
       b.booked_at + random() * INTERVAL '30 days',
       jsonb_build_object('status', 'pending'),
       jsonb_build_object('status', b.status)
FROM booking b WHERE random() < 0.45;

-- ---------------------------------------------------------------------
-- 8. Refresh planner statistics and print a summary
-- ---------------------------------------------------------------------
VACUUM (ANALYZE);

SELECT 'hotel' AS table_name, count(*) AS rows FROM hotel
UNION ALL SELECT 'room', count(*) FROM room
UNION ALL SELECT 'employee', count(*) FROM employee
UNION ALL SELECT 'guest', count(*) FROM guest
UNION ALL SELECT 'booking', count(*) FROM booking
UNION ALL SELECT 'booking_room', count(*) FROM booking_room
UNION ALL SELECT 'stay_record', count(*) FROM stay_record
UNION ALL SELECT 'service_order', count(*) FROM service_order
UNION ALL SELECT 'invoice', count(*) FROM invoice
UNION ALL SELECT 'payment', count(*) FROM payment
UNION ALL SELECT 'housekeeping_task', count(*) FROM housekeeping_task
UNION ALL SELECT 'maintenance_request', count(*) FROM maintenance_request
UNION ALL SELECT 'loyalty_transaction', count(*) FROM loyalty_transaction
UNION ALL SELECT 'audit_log', count(*) FROM audit_log
ORDER BY rows DESC;
