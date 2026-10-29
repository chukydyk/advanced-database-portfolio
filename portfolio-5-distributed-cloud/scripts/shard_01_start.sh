#!/usr/bin/env bash
# =====================================================================
# Portfolio 5 | shard_01_start.sh
# Starts a small sharded cluster on your own computer:
#   1 config server (port 27101), 2 shards (27102, 27103), 1 mongos router (27200)
# Each shard and the config server is a one-member replica set to keep it light.
# =====================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

banner "Starting config server and two shards"
start_mongod "shard/cfg" 27101 --configsvr --replSet cfgrs --oplogSize 128
start_mongod "shard/s1"  27102 --shardsvr  --replSet shard1rs --oplogSize 128
start_mongod "shard/s2"  27103 --shardsvr  --replSet shard2rs --oplogSize 128
for p in 27101 27102 27103; do wait_up "$p" && echo "port $p is up"; done
echo "Next: bash scripts/shard_02_init.sh"
