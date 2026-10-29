#!/usr/bin/env bash
# =====================================================================
# Portfolio 5 | common.sh
# Shared settings and helper functions. Sourced by the other scripts.
# If a tool is not on your PATH, set it before running, for example:
#   export MONGOD="/c/Program Files/MongoDB/Server/8.0/bin/mongod"
# =====================================================================
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1     # always work from the portfolio-5 folder

MONGOD="${MONGOD:-mongod}"
MONGOS="${MONGOS:-mongos}"
MONGOSH="${MONGOSH:-mongosh}"
MONGOIMPORT="${MONGOIMPORT:-mongoimport}"
P4_DATA="${P4_DATA:-../portfolio-4-nosql/data}"       # NDJSON files created in Portfolio 4

RS_NAME="homesrs"
RS_PORTS=(27018 27019 27020)
RS_URI="mongodb://127.0.0.1:27018,127.0.0.1:27019,127.0.0.1:27020/?replicaSet=homesrs"

mkdir -p data logs results

# start_mongod NAME PORT [extra mongod options...]  (runs in the background)
start_mongod() {
  local name="$1" port="$2"; shift 2
  mkdir -p "data/$name" "$(dirname "logs/$name.log")"
  nohup "$MONGOD" --dbpath "data/$name" --port "$port" --bind_ip 127.0.0.1 \
            --logpath "logs/$name.log" --wiredTigerCacheSizeGB 0.25 "$@" >/dev/null 2>&1 </dev/null &
}

# wait_up PORT : wait until a server answers on this port
wait_up() {
  local port="$1"
  for _ in $(seq 1 40); do
    "$MONGOSH" --quiet "mongodb://127.0.0.1:$port/?directConnection=true&serverSelectionTimeoutMS=1500" \
               --eval "db.runCommand({ping:1}).ok" 2>/dev/null | grep -q 1 && return 0
    sleep 1
  done
  echo "Timed out waiting for port $port" >&2; return 1
}

# stop_node PORT : shut down one server
stop_node() {
  "$MONGOSH" --quiet "mongodb://127.0.0.1:$1/?directConnection=true&serverSelectionTimeoutMS=2000" \
             --eval "try { db.getSiblingDB('admin').shutdownServer({force:true}) } catch (e) {}" >/dev/null 2>&1
}

# rs_primary_port : print the port of the current primary (asks each member directly)
rs_primary_port() {
  local p
  for p in "${RS_PORTS[@]}"; do
    if "$MONGOSH" --quiet "mongodb://127.0.0.1:$p/?directConnection=true&serverSelectionTimeoutMS=1000" \
         --eval 'print(db.hello().isWritablePrimary)' 2>/dev/null | grep -q true; then
      echo "$p"; return 0
    fi
  done
  return 1
}

# crash_node PORT : kill the server process abruptly (simulates a crash or power loss)
crash_node() {
  local pid
  pid=$("$MONGOSH" --quiet "mongodb://127.0.0.1:$1/?directConnection=true&serverSelectionTimeoutMS=2000" \
        --eval 'print(Number(db.serverStatus().pid))' 2>/dev/null | tail -1 | tr -d '[:space:]')
  [ -z "$pid" ] && { echo "Could not find the process id for port $1" >&2; return 1; }
  if command -v taskkill >/dev/null 2>&1; then taskkill //F //PID "$pid" >/dev/null 2>&1; else kill -9 "$pid"; fi
}

# rs_start_node PORT : (re)start one replica set member
rs_start_node() {
  local port="$1" idx=$(( $1 - 27017 ))
  start_mongod "rs/node$idx" "$port" --replSet "$RS_NAME" --oplogSize 128
}

banner() { printf '\n======================================================================\n%s\n======================================================================\n' "$1"; }
