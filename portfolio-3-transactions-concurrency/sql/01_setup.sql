-- =====================================================================
-- Portfolio 3 | 01_setup.sql
-- Creates what the transaction and concurrency demos need:
--   * sp_make_booking : an all-or-nothing booking procedure
--   * demo_* tables   : small tables so the demos never disturb real data
--   * demo_reset()    : puts everything back to a known starting state
-- Safe to run more than once. Requires Portfolio 1 schema and Portfolio 2 data.
-- =====================================================================
\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- 1. Demo tables (small copies / scratch tables)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS demo_loyalty_account, demo_rate, demo_duty_roster, demo_room_status;

CREATE TABLE demo_loyalty_account (guest_id INT PRIMARY KEY, points INT NOT NULL);
CREATE TABLE demo_rate            (rate_id INT PRIMARY KEY, hotel_id INT NOT NULL, nightly_rate NUMERIC(10,2) NOT NULL);
CREATE TABLE demo_duty_roster     (employee_id INT PRIMARY KEY, on_duty BOOLEAN NOT NULL);
CREATE TABLE demo_room_status     (room_id INT PRIMARY KEY, status TEXT NOT NULL);

-- ---------------------------------------------------------------------
-- 2. Reset procedure: restores demo tables and removes demo bookings
--    (demo bookings are the ones with check-in on or after 1 March 2027;
--     the generated data stops before that date)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE demo_reset()
LANGUAGE sql AS $$
    DELETE FROM payment WHERE invoice_id IN
        (SELECT i.invoice_id FROM invoice i JOIN booking b ON b.booking_id = i.booking_id
         WHERE b.check_in_date >= DATE '2027-03-01');
    DELETE FROM invoice WHERE booking_id IN
        (SELECT booking_id FROM booking WHERE check_in_date >= DATE '2027-03-01');
    DELETE FROM service_order WHERE booking_id IN
        (SELECT booking_id FROM booking WHERE check_in_date >= DATE '2027-03-01');
    DELETE FROM booking WHERE check_in_date >= DATE '2027-03-01';   -- booking_room rows cascade

    DELETE FROM demo_loyalty_account;
    INSERT INTO demo_loyalty_account VALUES (5, 1000);

    DELETE FROM demo_rate;
    INSERT INTO demo_rate SELECT rate_id, hotel_id, nightly_rate FROM rate WHERE rate_id <= 5;

    DELETE FROM demo_duty_roster;
    INSERT INTO demo_duty_roster VALUES (2, TRUE), (3, TRUE);      -- two receptionists on duty

    DELETE FROM demo_room_status;
    INSERT INTO demo_room_status VALUES (1, 'available'), (2, 'available'), (3, 'available');
$$;

CALL demo_reset();

-- ---------------------------------------------------------------------
-- 3. sp_make_booking: one atomic unit of work
--    Locks the room, validates, then creates the booking, the room
--    assignment, the invoice and a successful 30% deposit payment.
--    Any failure undoes ALL of it.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_make_booking(
    p_guest_id   INT,
    p_room_id    INT,
    p_check_in   DATE,
    p_check_out  DATE,
    p_source_id  INT,
    p_num_guests INT,
    INOUT p_booking_id INT DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_hotel   INT;
    v_cap     SMALLINT;
    v_status  VARCHAR;
    v_type    INT;
    v_rate    NUMERIC(10,2);
    v_nights  INT;
    v_sub     NUMERIC(12,2);
    v_tax     NUMERIC(12,2);
    v_total   NUMERIC(12,2);
    v_invoice INT;
BEGIN
    IF p_check_out <= p_check_in THEN
        RAISE EXCEPTION 'Check-out date must be after check-in date';
    END IF;

    -- Lock this room row: concurrent bookings of the SAME room queue up here
    SELECT r.hotel_id, rt.max_occupancy, r.status, r.room_type_id
      INTO v_hotel, v_cap, v_status, v_type
    FROM room r JOIN room_type rt ON rt.room_type_id = r.room_type_id
    WHERE r.room_id = p_room_id
    FOR UPDATE OF r;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Room % does not exist', p_room_id;
    END IF;
    IF v_status = 'maintenance' THEN
        RAISE EXCEPTION 'Room % is under maintenance', p_room_id;
    END IF;
    IF p_num_guests > v_cap THEN
        RAISE EXCEPTION 'Room % sleeps at most % guests (requested %)', p_room_id, v_cap, p_num_guests;
    END IF;

    SELECT nightly_rate INTO v_rate
    FROM rate
    WHERE hotel_id = v_hotel AND room_type_id = v_type
      AND p_check_in BETWEEN valid_from AND valid_to;
    IF v_rate IS NULL THEN
        RAISE EXCEPTION 'No rate defined for the requested dates';
    END IF;

    v_nights := p_check_out - p_check_in;
    v_sub    := v_rate * v_nights;
    v_tax    := round(v_sub * 0.075, 2);
    v_total  := v_sub + v_tax;

    INSERT INTO booking(guest_id, hotel_id, source_id, check_in_date, check_out_date, num_guests, status)
    VALUES (p_guest_id, v_hotel, p_source_id, p_check_in, p_check_out, p_num_guests, 'confirmed')
    RETURNING booking_id INTO p_booking_id;

    INSERT INTO booking_room(booking_id, room_id, rate_applied, stay_period)
    VALUES (p_booking_id, p_room_id, v_rate, daterange(p_check_in, p_check_out, '[)'));

    INSERT INTO invoice(booking_id, subtotal, tax_amount, total_amount, status)
    VALUES (p_booking_id, v_sub, v_tax, v_total, 'partially_paid')
    RETURNING invoice_id INTO v_invoice;

    INSERT INTO payment(invoice_id, method_id, payment_type, amount, status, gateway_token)
    VALUES (v_invoice, 1, 'deposit', round(v_total * 0.30, 2), 'successful',
            'tok_' || md5(v_invoice::text || clock_timestamp()::text));

EXCEPTION
    WHEN exclusion_violation THEN
        -- Raised by the GiST exclusion constraint from Portfolio 1
        RAISE EXCEPTION 'Room % is not available from % to %', p_room_id, p_check_in, p_check_out
              USING ERRCODE = 'P0001';
END;
$$;

-- Quick self-test (leaves no data behind)
BEGIN;
CALL sp_make_booking(1, 1, DATE '2027-03-01', DATE '2027-03-03', 1, 1);
ROLLBACK;
SELECT 'setup complete' AS status;
