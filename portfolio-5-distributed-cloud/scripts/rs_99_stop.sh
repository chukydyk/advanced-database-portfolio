#!/usr/bin/env bash
# Portfolio 5 | rs_99_stop.sh : stop the three replica set members
# Add --clean to delete their data folders as well (frees disk space).
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
for p in "${RS_PORTS[@]}"; do stop_node "$p"; done
sleep 3
echo "Replica set members stopped."
[ "$1" = "--clean" ] && rm -rf data/rs && echo "Data folders removed."
