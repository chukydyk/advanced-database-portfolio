#!/usr/bin/env bash
# Portfolio 5 | rs_02_initiate_and_seed.sh
# Creates the replica set and loads the hotel and review documents from Portfolio 4.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

banner "Initiating the replica set"
"$MONGOSH" --quiet "mongodb://127.0.0.1:27018/?directConnection=true" --file scripts/rs_02_initiate.js

banner "Loading data from Portfolio 4 ($P4_DATA)"
for c in hotels reviews; do
  if [ ! -f "$P4_DATA/$c.ndjson" ]; then
    echo "Missing $P4_DATA/$c.ndjson. Re-run the Portfolio 4 export (sql/01_export_to_ndjson.sql) or set P4_DATA." >&2
    exit 1
  fi
  "$MONGOIMPORT" --uri "$RS_URI" --db the_homes_ha --collection "$c" --file "$P4_DATA/$c.ndjson" \
                 --writeConcern majority 2>&1 | grep -E "imported|failed"
done
echo "Done. Next: mongosh \"$RS_URI\" --file scripts/rs_03_replication_demo.js"
