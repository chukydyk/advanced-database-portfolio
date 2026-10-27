#!/usr/bin/env bash
# =====================================================================
# Portfolio 4 | 02_import.sh
# Loads the four NDJSON files into MongoDB with mongoimport.
# Run from the portfolio-4-nosql folder, AFTER scripts/01_create_collections.js:
#   bash scripts/02_import.sh
# For MongoDB Atlas, set MONGO_URI first, for example:
#   export MONGO_URI="mongodb+srv://user:password@cluster0.xxxxx.mongodb.net"
# =====================================================================
MONGO_URI="${MONGO_URI:-mongodb://localhost:27017}"
DB="the_homes_nosql"

for c in hotels guest_profiles reviews activity_events; do
  echo "--- importing $c ---"
  mongoimport --uri "$MONGO_URI" --db "$DB" --collection "$c" --file "data/$c.ndjson" --numInsertionWorkers 4
done
echo "Import finished."
