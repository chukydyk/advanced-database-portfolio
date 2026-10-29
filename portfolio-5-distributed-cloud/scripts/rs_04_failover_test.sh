#!/usr/bin/env bash
# =====================================================================
# Portfolio 5 | rs_04_failover_test.sh
# Availability test: crash the PRIMARY while an application keeps writing,
# measure how long writes are blocked, and check that nothing acknowledged is lost.
#   bash scripts/rs_04_failover_test.sh | tee results/04_failover_output.txt
# Takes about one minute.
# =====================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
export HOMES_URI="$RS_URI" WRITER_SECONDS=40

banner "F1  Before: who is primary?"
P=$(rs_primary_port)
echo "Current primary: port $P"

banner "F2  Start the writer (40 seconds, w: majority) and crash the primary after 8 seconds"
"$MONGOSH" --quiet "$RS_URI" --file scripts/failover_writer.js > results/failover_writer_raw.txt 2>&1 &
WRITER=$!
sleep 8
echo "[$(date +%H:%M:%S)] CRASHING the primary on port $P (process killed, no clean shutdown)"
STOPPED=$(date +%s)
crash_node "$P"

for _ in $(seq 1 90); do
  NP=$(rs_primary_port)
  if [ -n "$NP" ] && [ "$NP" != "$P" ]; then
    echo "[$(date +%H:%M:%S)] New primary elected: port $NP (about $(( $(date +%s) - STOPPED )) seconds after the crash, as seen by this script)"
    break
  fi
  sleep 1
done

banner "F3  What the application saw"
wait "$WRITER"
cat results/failover_writer_raw.txt

banner "F4  Bring the old primary back: it should rejoin as a SECONDARY and catch up"
rs_start_node "$P"; wait_up "$P"
sleep 12
"$MONGOSH" --quiet "$RS_URI" --eval '
  const st = rs.status();
  printjson(st.members.map(m => ({ member: m.name, state: m.stateStr, health: m.health })));'

banner "F5  Verification: was any acknowledged write lost?"
ACKED=$(grep -o "ACKED=[0-9]*" results/failover_writer_raw.txt | cut -d= -f2)
"$MONGOSH" --quiet "$RS_URI" --eval "
  const col = db.getSiblingDB('the_homes_ha').failover_test;
  const stored = col.countDocuments();
  const last = col.find().sort({ seq: -1 }).limit(1).toArray()[0].seq;
  print('acknowledged by the writer : ' + $ACKED);
  print('documents stored           : ' + stored);
  print('highest sequence number    : ' + last + (last === stored ? '  (no gaps)' : '  (GAP FOUND)'));
  print(stored === $ACKED ? 'RESULT: no acknowledged write was lost' : 'RESULT: MISMATCH, investigate');"
