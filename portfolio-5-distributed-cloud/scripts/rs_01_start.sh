#!/usr/bin/env bash
# Portfolio 5 | rs_01_start.sh
# Starts three MongoDB servers (ports 27018, 27019, 27020) as members of replica set "homesrs".
# Your normal MongoDB service on port 27017 is NOT touched.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

banner "Starting 3 replica set members"
for p in "${RS_PORTS[@]}"; do rs_start_node "$p"; done
for p in "${RS_PORTS[@]}"; do wait_up "$p" && echo "port $p is up"; done
echo "All three servers are running. Next: bash scripts/rs_02_initiate_and_seed.sh"
