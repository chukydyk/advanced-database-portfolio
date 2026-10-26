#!/usr/bin/env bash
# =====================================================================
# Portfolio 3 | run_two_session_demos.sh
# Runs two psql sessions ("A" and "B") at the same time, with timed pauses,
# so concurrency problems and their fixes can be reproduced and captured.
# Every output line is labelled [A], [B] or [result], in time order.
#
# Usage (from the portfolio-3-transactions-concurrency folder, in Git Bash):
#   bash scripts/run_two_session_demos.sh                 # run every demo
#   bash scripts/run_two_session_demos.sh d1a d5a         # run chosen demos
#   bash scripts/run_two_session_demos.sh | tee results/03_two_session_output.txt
#
# Demo list:
#   d1a lost update (the problem)        d1b atomic UPDATE (fix 1)
#   d1c SELECT ... FOR UPDATE (fix 2)    d1d REPEATABLE READ (fix 3)
#   d2a last-room race, A commits        d2b last-room race, A rolls back
#   d3  last-room race via sp_make_booking
#   d4a dirty read                       d4b non-repeatable read (2 levels)
#   d4c phantom read (2 levels)
#   d5a write skew (REPEATABLE READ)     d5b write skew (SERIALIZABLE)
#   d6a deadlock                         d6b deadlock avoided (lock ordering)
#   d7  FOR UPDATE vs FOR UPDATE SKIP LOCKED
#
# Requirements: sql/01_setup.sql has been run. psql must be on your PATH.
# =====================================================================
export PSQL="${PSQL:-psql -X -q -U postgres -d the_homes}"

if [ -z "${PGPASSWORD:-}" ]; then
  read -r -s -p "PostgreSQL password for user postgres (typing is hidden): " PGPASSWORD
  export PGPASSWORD
  echo
fi

TS='ts=SELECT to_char(clock_timestamp(), $$HH24:MI:SS.MS$$) AS at'

sess()   { $PSQL -a -P pager=off -P null=- -v "$TS" -f -; }
reset()  { $PSQL -c 'CALL demo_reset();' >/dev/null 2>&1; }
banner() { printf '\n======================================================================\n%s\n======================================================================\n' "$1"; }
result() { $PSQL -P pager=off -P null=- -c "$1" 2>&1 | sed 's/^/[result] /'; }
pair() {  # $1 = title, $2 = script for session A, $3 = script for session B
  banner "$1"
  ( printf '%s\n' "$2" | sess 2>&1 | sed -u 's/^/[A] /' ) &
  ( printf '%s\n' "$3" | sess 2>&1 | sed -u 's/^/[B] /' ) &
  wait
}
level() { echo "${1//@LEVEL@/$2}"; }   # swap @LEVEL@ for an isolation level

# ---------------------------------------------------------------------
# D1  Lost update on a loyalty balance (starts at 1000; A adds 100, B adds 200)
# ---------------------------------------------------------------------
d1a() { reset
A=$(cat <<'EOF'
BEGIN;
SELECT points AS bal FROM demo_loyalty_account WHERE guest_id = 5 \gset
\echo A read the balance: :bal
SELECT pg_sleep(2) AS _ \gset
UPDATE demo_loyalty_account SET points = :bal + 100 WHERE guest_id = 5;
COMMIT;
\echo A committed (wrote balance + 100)
EOF
)
B=$(cat <<'EOF'
SELECT pg_sleep(0.5) AS _ \gset
BEGIN;
SELECT points AS bal FROM demo_loyalty_account WHERE guest_id = 5 \gset
\echo B read the balance: :bal
SELECT pg_sleep(2) AS _ \gset
UPDATE demo_loyalty_account SET points = :bal + 200 WHERE guest_id = 5;
COMMIT;
\echo B committed (wrote balance + 200)
EOF
)
pair "D1a  LOST UPDATE: read-modify-write at READ COMMITTED (the problem)" "$A" "$B"
result "SELECT points AS final_balance, 1300 AS correct_balance FROM demo_loyalty_account WHERE guest_id = 5"; }

d1b() { reset
A=$(cat <<'EOF'
BEGIN;
UPDATE demo_loyalty_account SET points = points + 100 WHERE guest_id = 5;
\echo A updated the row and holds its lock
SELECT pg_sleep(2) AS _ \gset
COMMIT;
\echo A committed
EOF
)
B=$(cat <<'EOF'
SELECT pg_sleep(0.5) AS _ \gset
BEGIN;
\echo B now updates the same row and must wait for A
UPDATE demo_loyalty_account SET points = points + 200 WHERE guest_id = 5;
\echo B update finished (it waited, then applied on top of the change A made)
COMMIT;
EOF
)
pair "D1b  FIX 1: atomic UPDATE (points = points + n) lets the database serialise the writes" "$A" "$B"
result "SELECT points AS final_balance, 1300 AS correct_balance FROM demo_loyalty_account WHERE guest_id = 5"; }

d1c() { reset
A=$(cat <<'EOF'
BEGIN;
SELECT points AS bal FROM demo_loyalty_account WHERE guest_id = 5 FOR UPDATE \gset
\echo A read the balance and locked the row: :bal
SELECT pg_sleep(2) AS _ \gset
UPDATE demo_loyalty_account SET points = :bal + 100 WHERE guest_id = 5;
COMMIT;
\echo A committed
EOF
)
B=$(cat <<'EOF'
SELECT pg_sleep(0.5) AS _ \gset
BEGIN;
\echo B asks for the balance with FOR UPDATE and must wait
SELECT points AS bal FROM demo_loyalty_account WHERE guest_id = 5 FOR UPDATE \gset
\echo B finally read the balance: :bal
UPDATE demo_loyalty_account SET points = :bal + 200 WHERE guest_id = 5;
COMMIT;
\echo B committed
EOF
)
pair "D1c  FIX 2: pessimistic locking with SELECT ... FOR UPDATE" "$A" "$B"
result "SELECT points AS final_balance, 1300 AS correct_balance FROM demo_loyalty_account WHERE guest_id = 5"; }

d1d() { reset
A=$(cat <<'EOF'
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT points AS bal FROM demo_loyalty_account WHERE guest_id = 5 \gset
\echo A read the balance: :bal
SELECT pg_sleep(2) AS _ \gset
UPDATE demo_loyalty_account SET points = :bal + 100 WHERE guest_id = 5;
COMMIT;
\echo A committed
EOF
)
B=$(cat <<'EOF'
SELECT pg_sleep(0.5) AS _ \gset
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT points AS bal FROM demo_loyalty_account WHERE guest_id = 5 \gset
\echo B read the balance: :bal
SELECT pg_sleep(2) AS _ \gset
UPDATE demo_loyalty_account SET points = :bal + 200 WHERE guest_id = 5;
ROLLBACK;
\echo B was refused and must retry its transaction
EOF
)
pair "D1d  FIX 3: REPEATABLE READ detects the conflict and aborts one transaction" "$A" "$B"
result "SELECT points AS final_balance FROM demo_loyalty_account WHERE guest_id = 5"; }

# ---------------------------------------------------------------------
# D2  Two receptionists book the LAST free slot of room 2 at the same moment
# ---------------------------------------------------------------------
d2() { reset
local END_A="$1" TITLE="$2"
A=$(cat <<EOF
BEGIN;
\\echo A inserts a booking for room 2, 10-13 April 2027 (not committed yet)
WITH b AS (INSERT INTO booking(guest_id, hotel_id, source_id, check_in_date, check_out_date, num_guests, status)
           VALUES (11, 1, 1, '2027-04-10', '2027-04-13', 1, 'confirmed') RETURNING booking_id)
INSERT INTO booking_room(booking_id, room_id, rate_applied, stay_period)
SELECT booking_id, 2, 50, daterange('2027-04-10', '2027-04-13', '[)') FROM b;
SELECT pg_sleep(3) AS _ \\gset
$END_A;
\\echo A finished with $END_A
EOF
)
B=$(cat <<'EOF'
SELECT pg_sleep(1) AS _ \gset
BEGIN;
\echo B tries to book the SAME room for overlapping dates, 11-14 April
:ts;
WITH b AS (INSERT INTO booking(guest_id, hotel_id, source_id, check_in_date, check_out_date, num_guests, status)
           VALUES (12, 1, 1, '2027-04-11', '2027-04-14', 1, 'confirmed') RETURNING booking_id)
INSERT INTO booking_room(booking_id, room_id, rate_applied, stay_period)
SELECT booking_id, 2, 50, daterange('2027-04-11', '2027-04-14', '[)') FROM b;
:ts;
COMMIT;
\echo B finished
EOF
)
pair "$TITLE" "$A" "$B"
result "SELECT b.booking_id, b.guest_id, br.room_id, br.stay_period FROM booking b JOIN booking_room br USING (booking_id) WHERE br.room_id = 2 AND b.check_in_date >= DATE '2027-03-01' ORDER BY 1"; }
d2a() { d2 COMMIT   "D2a  LAST-ROOM RACE: B waits for A, then the exclusion constraint rejects B (A commits)"; }
d2b() { d2 ROLLBACK "D2b  LAST-ROOM RACE: B waits for A, then succeeds because A rolled back"; }

# ---------------------------------------------------------------------
# D3  Same race, but through the sp_make_booking procedure
# ---------------------------------------------------------------------
d3() { reset
A=$(cat <<'EOF'
BEGIN;
\echo A calls sp_make_booking for room 3, 10-13 April 2027
CALL sp_make_booking(21, 3, '2027-04-10', '2027-04-13', 1, 1);
\echo A holds the room lock for 3 seconds before committing
SELECT pg_sleep(3) AS _ \gset
COMMIT;
\echo A committed
EOF
)
B=$(cat <<'EOF'
SELECT pg_sleep(1) AS _ \gset
\echo B calls sp_make_booking for the SAME room and overlapping dates
:ts;
CALL sp_make_booking(22, 3, '2027-04-11', '2027-04-14', 1, 1);
:ts;
EOF
)
pair "D3  LAST-ROOM RACE through sp_make_booking: lock on the room row, then a friendly error" "$A" "$B"
result "SELECT (SELECT count(*) FROM booking WHERE check_in_date >= DATE '2027-03-01') AS bookings, (SELECT count(*) FROM invoice i JOIN booking b USING (booking_id) WHERE b.check_in_date >= DATE '2027-03-01') AS invoices, (SELECT count(*) FROM payment p JOIN invoice i USING (invoice_id) JOIN booking b USING (booking_id) WHERE b.check_in_date >= DATE '2027-03-01') AS payments"; }

# ---------------------------------------------------------------------
# D4  Isolation levels: dirty read, non-repeatable read, phantom read
# ---------------------------------------------------------------------
d4a() { reset
A=$(cat <<'EOF'
BEGIN;
UPDATE demo_rate SET nightly_rate = 999 WHERE rate_id = 1;
\echo A changed rate 1 to 999 but has NOT committed
SELECT pg_sleep(2) AS _ \gset
ROLLBACK;
\echo A rolled back
EOF
)
B=$(cat <<'EOF'
SELECT pg_sleep(0.7) AS _ \gset
BEGIN ISOLATION LEVEL READ UNCOMMITTED;
\echo B reads rate 1 at the lowest isolation level (READ UNCOMMITTED)
SELECT rate_id, nightly_rate FROM demo_rate WHERE rate_id = 1;
COMMIT;
EOF
)
pair "D4a  DIRTY READ: PostgreSQL never shows uncommitted data, even at READ UNCOMMITTED" "$A" "$B"; }

d4b() { reset
A=$(cat <<'EOF'
BEGIN ISOLATION LEVEL @LEVEL@;
SELECT nightly_rate AS first_read FROM demo_rate WHERE rate_id = 1;
SELECT pg_sleep(2) AS _ \gset
SELECT nightly_rate AS second_read FROM demo_rate WHERE rate_id = 1;
COMMIT;
EOF
)
B=$(cat <<'EOF'
SELECT pg_sleep(0.7) AS _ \gset
UPDATE demo_rate SET nightly_rate = nightly_rate + 10 WHERE rate_id = 1;
\echo B changed the rate by +10 and committed (autocommit)
EOF
)
pair "D4b-1  NON-REPEATABLE READ at READ COMMITTED: A sees two different values" "$(level "$A" "READ COMMITTED")" "$B"
reset
pair "D4b-2  NON-REPEATABLE READ at REPEATABLE READ: A sees the same value twice" "$(level "$A" "REPEATABLE READ")" "$B"; }

d4c() { reset
A=$(cat <<'EOF'
BEGIN ISOLATION LEVEL @LEVEL@;
SELECT count(*) AS first_count FROM demo_rate WHERE hotel_id = 1;
SELECT pg_sleep(2) AS _ \gset
SELECT count(*) AS second_count FROM demo_rate WHERE hotel_id = 1;
COMMIT;
EOF
)
B=$(cat <<'EOF'
SELECT pg_sleep(0.7) AS _ \gset
INSERT INTO demo_rate VALUES (100, 1, 55.00);
\echo B inserted a new matching row and committed (autocommit)
EOF
)
pair "D4c-1  PHANTOM READ at READ COMMITTED: a new row appears inside A's transaction" "$(level "$A" "READ COMMITTED")" "$B"
reset
pair "D4c-2  PHANTOM READ at REPEATABLE READ: PostgreSQL snapshot hides the new row" "$(level "$A" "REPEATABLE READ")" "$B"; }

# ---------------------------------------------------------------------
# D5  Write skew: rule = at least ONE receptionist must stay on duty
# ---------------------------------------------------------------------
d5() { reset
A=$(cat <<'EOF'
BEGIN ISOLATION LEVEL @LEVEL@;
SELECT count(*) >= 2 AS ok FROM demo_duty_roster WHERE on_duty \gset
\echo A checks the rule: at least 2 on duty so it is safe to leave? :ok
SELECT pg_sleep(1.5) AS _ \gset
\if :ok
  \echo A asks to go off duty (UPDATE sent)
  UPDATE demo_duty_roster SET on_duty = FALSE WHERE employee_id = 2;
\endif
COMMIT;
\echo A finished
EOF
)
B=$(cat <<'EOF'
SELECT pg_sleep(0.3) AS _ \gset
BEGIN ISOLATION LEVEL @LEVEL@;
SELECT count(*) >= 2 AS ok FROM demo_duty_roster WHERE on_duty \gset
\echo B checks the rule: at least 2 on duty so it is safe to leave? :ok
SELECT pg_sleep(2.7) AS _ \gset
\if :ok
  \echo B asks to go off duty (UPDATE sent)
  UPDATE demo_duty_roster SET on_duty = FALSE WHERE employee_id = 3;
\endif
COMMIT;
\echo B finished
EOF
)
pair "$2" "$(level "$A" "$1")" "$(level "$B" "$1")"
result "SELECT count(*) FILTER (WHERE on_duty) AS receptionists_on_duty, 'rule: must be at least 1' AS note FROM demo_duty_roster"; }
d5a() { d5 "REPEATABLE READ" "D5a  WRITE SKEW at REPEATABLE READ: both leave, the rule is broken"; }
d5b() { d5 "SERIALIZABLE"    "D5b  WRITE SKEW at SERIALIZABLE: one transaction is aborted, the rule holds"; }

# ---------------------------------------------------------------------
# D6  Deadlock and how to avoid it
# ---------------------------------------------------------------------
d6a() { reset
A=$(cat <<'EOF'
BEGIN;
UPDATE demo_room_status SET status = 'cleaning' WHERE room_id = 1;
\echo A locked room 1
SELECT pg_sleep(1.5) AS _ \gset
\echo A now wants room 2
UPDATE demo_room_status SET status = 'cleaning' WHERE room_id = 2;
COMMIT;
\echo A finished
EOF
)
B=$(cat <<'EOF'
SELECT pg_sleep(0.5) AS _ \gset
BEGIN;
UPDATE demo_room_status SET status = 'cleaning' WHERE room_id = 2;
\echo B locked room 2
SELECT pg_sleep(1.5) AS _ \gset
\echo B now wants room 1
UPDATE demo_room_status SET status = 'cleaning' WHERE room_id = 1;
COMMIT;
\echo B finished
EOF
)
pair "D6a  DEADLOCK: A locks room 1 then 2, B locks room 2 then 1" "$A" "$B"
result "SELECT room_id, status FROM demo_room_status ORDER BY room_id"; }

d6b() { reset
A=$(cat <<'EOF'
BEGIN;
UPDATE demo_room_status SET status = 'cleaning' WHERE room_id = 1;
\echo A locked room 1
SELECT pg_sleep(1.5) AS _ \gset
UPDATE demo_room_status SET status = 'cleaning' WHERE room_id = 2;
\echo A locked room 2
COMMIT;
\echo A finished
EOF
)
B=$(cat <<'EOF'
SELECT pg_sleep(0.5) AS _ \gset
BEGIN;
\echo B also locks room 1 FIRST (same order as A), so it waits
UPDATE demo_room_status SET status = 'cleaning' WHERE room_id = 1;
\echo B locked room 1
UPDATE demo_room_status SET status = 'cleaning' WHERE room_id = 2;
\echo B locked room 2
COMMIT;
\echo B finished
EOF
)
pair "D6b  DEADLOCK AVOIDED: every transaction locks rooms in the same order (lowest room_id first)" "$A" "$B"
result "SELECT room_id, status FROM demo_room_status ORDER BY room_id"; }

# ---------------------------------------------------------------------
# D7  Two receptionists each grab "the next free room" from a pool of 3 free rooms
# ---------------------------------------------------------------------
d7() { reset
A=$(cat <<'EOF'
BEGIN;
SELECT room_id FROM demo_room_status
WHERE status = 'available'
ORDER BY room_id LIMIT 1 @MODE@;
\echo A picked a room and keeps it locked for 2 seconds
SELECT pg_sleep(2) AS _ \gset
COMMIT;
EOF
)
B=$(cat <<'EOF'
SELECT pg_sleep(0.5) AS _ \gset
BEGIN;
\echo B asks for the next free room
:ts;
SELECT room_id FROM demo_room_status
WHERE status = 'available'
ORDER BY room_id LIMIT 1 @MODE@;
:ts;
COMMIT;
EOF
)
local M1="FOR UPDATE" M2="FOR UPDATE SKIP LOCKED"
pair "D7a  FOR UPDATE: B waits for A, then receives THE SAME ROOM (double-assignment risk)" "${A//@MODE@/$M1}" "${B//@MODE@/$M1}"
pair "D7b  FOR UPDATE SKIP LOCKED: B immediately receives a DIFFERENT room" "${A//@MODE@/$M2}" "${B//@MODE@/$M2}"; }

# ---------------------------------------------------------------------
ALL="d1a d1b d1c d1d d2a d2b d3 d4a d4b d4c d5a d5b d6a d6b d7"
for demo in ${@:-$ALL}; do
  if declare -F "$demo" >/dev/null; then "$demo"; else echo "Unknown demo: $demo" >&2; fi
done
reset
banner "All demos finished. Demo data has been reset."
