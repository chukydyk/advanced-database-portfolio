-- =====================================================================
-- Portfolio 3 | 99_cleanup.sql  (optional, run when you have finished)
-- Removes all demo bookings and demo tables. Keeps sp_make_booking
-- because it is part of your deliverable.
-- =====================================================================
CALL demo_reset();                 -- deletes demo bookings, payments and invoices
DROP TABLE IF EXISTS demo_loyalty_account, demo_rate, demo_duty_roster, demo_room_status;
DROP PROCEDURE IF EXISTS demo_reset();
SELECT 'cleanup complete' AS status;
