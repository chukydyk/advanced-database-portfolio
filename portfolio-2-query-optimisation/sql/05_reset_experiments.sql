-- =====================================================================
-- Portfolio 2 | 05_reset_experiments.sql
-- Removes every object created by 04_optimisation_experiments.sql so you
-- can repeat the experiments from the original baseline.
-- (Your data and the Portfolio 1 schema are not touched.)
-- =====================================================================
DROP INDEX IF EXISTS idx_guest_last_name;
DROP INDEX IF EXISTS idx_guest_lower_last_name;
DROP INDEX IF EXISTS idx_payment_failed_paid_at;
DROP INDEX IF EXISTS idx_invoice_issued_cover;
DROP TABLE IF EXISTS booking_part;
DROP TABLE IF EXISTS booking_flat;
ANALYZE;
