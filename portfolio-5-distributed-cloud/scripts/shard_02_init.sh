#!/usr/bin/env bash
# Portfolio 5 | shard_02_init.sh
# Initiates the three replica sets, starts the mongos router and registers both shards.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

init_rs() {  # PORT JSON-config
  "$MONGOSH" --quiet "mongodb://127.0.0.1:$1/?directConnection=true" \
     --eval "rs.initiate($2); let n=0; while (!db.hello().isWritablePrimary && n++ < 60) sleep(1000); print('port $1 primary: ' + db.hello().isWritablePrimary)"
}

banner "Initiating replica sets"
init_rs 27101 "{_id:'cfgrs', configsvr:true, members:[{_id:0, host:'127.0.0.1:27101'}]}"
init_rs 27102 "{_id:'shard1rs', members:[{_id:0, host:'127.0.0.1:27102'}]}"
init_rs 27103 "{_id:'shard2rs', members:[{_id:0, host:'127.0.0.1:27103'}]}"

banner "Starting the mongos router on port 27200"
mkdir -p logs/shard
nohup "$MONGOS" --configdb cfgrs/127.0.0.1:27101 --port 27200 --bind_ip 127.0.0.1 \
      --logpath logs/shard/mongos.log >/dev/null 2>&1 </dev/null &
wait_up 27200 && echo "mongos is up"

banner "Registering the shards"
"$MONGOSH" --quiet "mongodb://127.0.0.1:27200/?directConnection=true" --eval '
  printjson(sh.addShard("shard1rs/127.0.0.1:27102"));
  printjson(sh.addShard("shard2rs/127.0.0.1:27103"));'
echo "Next: mongosh mongodb://127.0.0.1:27200 --file scripts/shard_03_configure.js"
