#!/usr/bin/env bash
# =====================================================================
# Portfolio 5 | rs_06_partition_cap.sh
# CAP theorem in practice: remove the majority of the replica set. The lone
# surviving member chooses consistency over availability: it refuses writes
# but can still serve (possibly stale) reads.
#   bash scripts/rs_06_partition_cap.sh | tee results/06_cap_output.txt
# =====================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

P=$(rs_primary_port)
OTHERS=()
for p in "${RS_PORTS[@]}"; do [ "$p" != "$P" ] && OTHERS+=("$p"); done

banner "P1  Healthy cluster: primary is port $P"

banner "P2  Failure: the two other members (${OTHERS[*]}) become unreachable"
for p in "${OTHERS[@]}"; do stop_node "$p"; done
echo "Waiting 15 seconds for the survivor to notice it has lost its majority..."
sleep 15

banner "P3  What the lone survivor (port $P) does"
"$MONGOSH" --quiet --port "$P" --eval '
  const h = db.hello();
  print("isWritablePrimary: " + h.isWritablePrimary + " | secondary: " + h.secondary);
  const col = db.getSiblingDB("the_homes_ha").reviews;
  try { col.insertOne({ _id: "partition-demo", note: "write during partition" }); print("WRITE accepted (unexpected)"); }
  catch (e) { print("WRITE refused  -> " + (e.codeName || e.name) + ": " + String(e.message).slice(0, 80)); }
  db.getMongo().setReadPref("secondaryPreferred");
  print("READ still works -> reviews in collection: " + col.countDocuments() + " (data may be stale)");'
echo "Consistency was kept (no split brain), but write availability was lost."

banner "P4  Recovery: restart the two members"
for p in "${OTHERS[@]}"; do rs_start_node "$p"; done
for p in "${OTHERS[@]}"; do wait_up "$p"; done
for _ in $(seq 1 60); do NP=$(rs_primary_port); [ -n "$NP" ] && break; sleep 1; done
echo "Primary after recovery: port $NP"
"$MONGOSH" --quiet "$RS_URI" --eval '
  const t = db.getSiblingDB("the_homes_ha").partition_test;
  t.insertOne({ ok: 1 }, { writeConcern: { w: "majority" } });
  print("WRITE accepted again with w: majority. Cluster is healthy.");
  t.drop(); print("Test collection removed.");'
