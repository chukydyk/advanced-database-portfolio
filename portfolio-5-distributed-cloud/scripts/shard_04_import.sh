#!/usr/bin/env bash
# Portfolio 5 | shard_04_import.sh
# Loads the Portfolio 4 events and guest profiles THROUGH the mongos router, so the
# cluster places every document on the right shard while it loads.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
banner "Importing through mongos (about 1 to 3 minutes)"
for c in activity_events guest_profiles; do
  [ -f "$P4_DATA/$c.ndjson" ] || { echo "Missing $P4_DATA/$c.ndjson (run the Portfolio 4 export or set P4_DATA)" >&2; exit 1; }
  "$MONGOIMPORT" --uri "mongodb://127.0.0.1:27200" --db the_homes_shard --collection "$c" \
                 --file "$P4_DATA/$c.ndjson" --numInsertionWorkers 2 2>&1 | grep -E "imported|failed"
done
echo "Next: mongosh mongodb://127.0.0.1:27200 --file scripts/shard_05_distribution.js"
