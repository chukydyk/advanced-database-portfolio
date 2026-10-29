#!/usr/bin/env bash
# Portfolio 5 | shard_99_stop.sh : stop the sharded cluster (add --clean to delete its data)
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
for p in 27200 27102 27103 27101; do stop_node "$p"; done
sleep 3
echo "Sharded cluster stopped."
[ "$1" = "--clean" ] && rm -rf data/shard logs/shard && echo "Data folders removed."
