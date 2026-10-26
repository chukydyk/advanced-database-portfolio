-- =====================================================================
-- Portfolio 3 | 02_commit_rollback.sql
-- Single-session demonstrations of atomicity, COMMIT, ROLLBACK,
-- SAVEPOINT and an all-or-nothing stored procedure.
--
-- Run (output AND error messages are captured in the file):
--   psql -U postgres -d the_homes -f sql/02_commit_rollback.sql > results/02_commit_rollback_output.txt 2>&1
-- Errors are EXPECTED in T2, T4 and T5: they are the point of the demo.
-- =====================================================================
\set ON_ERROR_STOP off
\pset pager off
\pset null '-'

CALL demo_reset();

-- A reusable row-count snapshot
\set counts 'SELECT (SELECT count(*) FROM booking) AS bookings, (SELECT count(*) FROM booking_room) AS booking_rooms, (SELECT count(*) FROM invoice) AS invoices, (SELECT count(*) FROM payment) AS payments'

\echo
\echo ======================================================================
\echo Starting row counts
\echo ======================================================================
:counts;

-- =====================================================================
\echo
\echo ======================================================================
\echo T1  COMMIT: a complete booking made of four dependent inserts
\echo     (booking, room assignment, invoice, deposit payment)
\echo ======================================================================
BEGIN;

INSERT INTO booking(guest_id, hotel_id, source_id, check_in_date, check_out_date, num_guests, status)
VALUES (1, 1, 1, '2027-03-10', '2027-03-13', 1, 'confirmed')
RETURNING booking_id \gset

INSERT INTO booking_room(booking_id, room_id, rate_applied, stay_period)
SELECT :booking_id, 1, nightly_rate, daterange('2027-03-10', '2027-03-13', '[)')
FROM rate WHERE hotel_id = 1 AND room_type_id = 1 AND DATE '2027-03-10' BETWEEN valid_from AND valid_to;

INSERT INTO invoice(booking_id, subtotal, tax_amount, total_amount, status)
SELECT :booking_id, rate_applied * 3, round(rate_applied * 3 * 0.075, 2),
       rate_applied * 3 + round(rate_applied * 3 * 0.075, 2), 'partially_paid'
FROM booking_room WHERE booking_id = :booking_id
RETURNING invoice_id \gset

INSERT INTO payment(invoice_id, method_id, payment_type, amount, status, gateway_token)
SELECT :invoice_id, 1, 'deposit', round(total_amount * 0.30, 2), 'successful', 'tok_demo_t1'
FROM invoice WHERE invoice_id = :invoice_id;

\echo Inside the transaction (visible to this session only):
:counts;
COMMIT;

\echo After COMMIT (permanent, visible to everyone):
:counts;
SELECT b.booking_id, b.status, i.invoice_id, i.total_amount, p.amount AS deposit
FROM booking b JOIN invoice i ON i.booking_id = b.booking_id JOIN payment p ON p.invoice_id = i.invoice_id
WHERE b.booking_id = :booking_id;

-- =====================================================================
\echo
\echo ======================================================================
\echo T2  ROLLBACK after an error: the deposit uses a payment method that does
\echo     not exist (method_id 99). Atomicity means NOTHING from this
\echo     transaction may survive, including the booking and invoice.
\echo ======================================================================
\echo Counts before:
:counts;
BEGIN;

INSERT INTO booking(guest_id, hotel_id, source_id, check_in_date, check_out_date, num_guests, status)
VALUES (2, 1, 1, '2027-03-10', '2027-03-13', 1, 'confirmed')
RETURNING booking_id \gset

INSERT INTO booking_room(booking_id, room_id, rate_applied, stay_period)
VALUES (:booking_id, 3, 60, daterange('2027-03-10', '2027-03-13', '[)'));

INSERT INTO invoice(booking_id, subtotal, tax_amount, total_amount, status)
VALUES (:booking_id, 180, 13.50, 193.50, 'partially_paid')
RETURNING invoice_id \gset

\echo Next statement fails (foreign key violation):
INSERT INTO payment(invoice_id, method_id, payment_type, amount, status, gateway_token)
VALUES (:invoice_id, 99, 'deposit', 58.05, 'successful', 'tok_demo_t2');

\echo The transaction is now in an aborted state. Further commands are refused:
SELECT count(*) FROM booking;

ROLLBACK;
\echo Counts after ROLLBACK (must equal the counts before):
:counts;

-- =====================================================================
\echo
\echo ======================================================================
\echo T3  ROLLBACK by choice: the guest abandons checkout
\echo ======================================================================
BEGIN;
INSERT INTO booking(guest_id, hotel_id, source_id, check_in_date, check_out_date, num_guests, status)
VALUES (3, 1, 2, '2027-03-20', '2027-03-22', 1, 'pending')
RETURNING booking_id \gset
\echo Visible inside the transaction:
SELECT booking_id, status, check_in_date FROM booking WHERE booking_id = :booking_id;
ROLLBACK;
\echo After ROLLBACK the booking no longer exists (0 rows expected):
SELECT booking_id, status, check_in_date FROM booking WHERE booking_id = :booking_id;

-- =====================================================================
\echo
\echo ======================================================================
\echo T4  SAVEPOINT: keep the booking, undo only the failed optional extra
\echo ======================================================================
BEGIN;
INSERT INTO booking(guest_id, hotel_id, source_id, check_in_date, check_out_date, num_guests, status)
VALUES (4, 1, 1, '2027-03-25', '2027-03-27', 1, 'confirmed')
RETURNING booking_id \gset
INSERT INTO booking_room(booking_id, room_id, rate_applied, stay_period)
VALUES (:booking_id, 4, 60, daterange('2027-03-25', '2027-03-27', '[)'));

SAVEPOINT before_spa;
\echo Adding a spa order for a service that does not exist (fails):
INSERT INTO service_order(booking_id, service_id, quantity, unit_price_charged)
VALUES (:booking_id, 9999, 1, 60);
ROLLBACK TO SAVEPOINT before_spa;
\echo Rolled back to the savepoint. The booking is still in the transaction:
SELECT booking_id, status FROM booking WHERE booking_id = :booking_id;
COMMIT;

\echo After COMMIT: booking kept (1 row), failed spa order absent (0 rows):
SELECT (SELECT count(*) FROM booking WHERE booking_id = :booking_id)       AS booking_rows,
       (SELECT count(*) FROM service_order WHERE booking_id = :booking_id) AS service_order_rows;

-- =====================================================================
\echo
\echo ======================================================================
\echo T5  Stored procedure sp_make_booking: all-or-nothing in one call
\echo ======================================================================
\echo T5a  Valid booking:
:counts;
CALL sp_make_booking(5, 5, '2027-04-01', '2027-04-04', 1, 1);
:counts;

\echo T5b  Same room, overlapping dates: friendly error, nothing partially saved:
CALL sp_make_booking(6, 5, '2027-04-02', '2027-04-05', 1, 1);
:counts;

\echo T5c  Too many guests for a single room (room 5 sleeps 1 guest):
CALL sp_make_booking(7, 5, '2027-05-01', '2027-05-03', 1, 3);
:counts;

\echo T5d  Check-out before check-in:
CALL sp_make_booking(8, 5, '2027-05-10', '2027-05-08', 1, 1);
:counts;

-- =====================================================================
\echo
\echo ======================================================================
\echo T6  Durability settings that make COMMIT permanent
\echo ======================================================================
SHOW synchronous_commit;
SHOW wal_level;
SHOW fsync;

-- Return the database to its normal state
CALL demo_reset();
\echo
\echo Demo bookings removed. Final counts (should equal the starting counts):
:counts;
