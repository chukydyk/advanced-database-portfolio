// =====================================================================
// Portfolio 5 | rs_05_consistency.js   (mongosh)
// Consistency versus speed: write concerns, and a stale read from a
// secondary that is deliberately 5 seconds behind (eventual consistency).
//
//   mongosh "mongodb://127.0.0.1:27018,127.0.0.1:27019,127.0.0.1:27020/?replicaSet=homesrs" \
//           --file scripts/rs_05_consistency.js > results/05_consistency_output.txt
// All three members must be running. The delayed member is restored at the end.
// =====================================================================
const dbh = db.getSiblingDB("the_homes_ha");
const col = dbh.consistency_test;
const head = (t) => print("\n" + "=".repeat(70) + "\n" + t + "\n" + "=".repeat(70));

head("S1  Cost of safety: 300 inserts with three different write concerns");
col.drop();
function timeWrites(label, wc) {
  const n = 300, t = Date.now();
  for (let i = 0; i < n; i++) col.insertOne({ i: i, wc: label }, { writeConcern: wc });
  const ms = Date.now() - t;
  print(`${label.padEnd(28)} total ${String(ms).padStart(5)} ms | average ${(ms / n).toFixed(2)} ms per write`);
}
timeWrites("w:1 (primary only)", { w: 1, j: false });
timeWrites("w:majority", { w: "majority", j: false });
timeWrites("w:majority + journal", { w: "majority", j: true });
print("w:1 returns when only the primary has the write: fastest, but the write can be lost if the primary fails");
print("before a secondary copies it. w:majority waits for a majority, so the write survives any single failure.");

head("S2  Eventual consistency: a secondary that is 5 seconds behind");
const st = rs.status();
const prim = st.members.find(m => m.stateStr === "PRIMARY");
const secs = st.members.filter(m => m.stateStr === "SECONDARY");
const slow = secs[0], fast = secs[1];
const port = (m) => m.name.split(":")[1];
print(`primary: ${prim.name} | normal secondary: ${fast.name} | delayed secondary: ${slow.name}`);

let cfg = rs.conf();
let idx = cfg.members.findIndex(m => m.host === slow.name);
cfg.members[idx].priority = 0;
cfg.members[idx].secondaryDelaySecs = 5;
rs.reconfig(cfg);
sleep(4000);
print("Delayed secondary configured (applies writes 5 s late).");

col.deleteMany({ _id: "stale-demo" });
col.insertOne({ _id: "stale-demo", booking: "room 12 reserved" }, { writeConcern: { w: "majority" } });
print("Wrote the document to the primary and a majority has acknowledged it.");

function readFrom(m) {
  const c = new Mongo(`mongodb://127.0.0.1:${port(m)}/?directConnection=true&readPreference=secondaryPreferred`);
  return c.getDB("the_homes_ha").consistency_test.findOne({ _id: "stale-demo" }) !== null;
}
print(`Read immediately  | primary ${prim.name}: ${readFrom(prim)} | normal secondary: ${readFrom(fast)} | delayed secondary: ${readFrom(slow)}`);
sleep(6500);
print(`Read 6.5 s later  | primary ${prim.name}: ${readFrom(prim)} | normal secondary: ${readFrom(fast)} | delayed secondary: ${readFrom(slow)}`);
print("A reader on the delayed secondary saw STALE data (document missing) and then caught up: eventual consistency.");

cfg = rs.conf();
idx = cfg.members.findIndex(m => m.host === slow.name);
cfg.members[idx].priority = 1;
cfg.members[idx].secondaryDelaySecs = 0;
rs.reconfig(cfg);
print("\nDelay removed, replica set restored to normal.");
col.drop();
