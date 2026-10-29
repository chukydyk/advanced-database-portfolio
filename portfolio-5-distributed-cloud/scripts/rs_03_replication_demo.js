// =====================================================================
// Portfolio 5 | rs_03_replication_demo.js   (mongosh)
// Shows replication at work: member status, a write replicated to every
// member, and the oplog entry that carried it.
//
//   mongosh "mongodb://127.0.0.1:27018,127.0.0.1:27019,127.0.0.1:27020/?replicaSet=homesrs" \
//           --file scripts/rs_03_replication_demo.js
// =====================================================================
const dbh = db.getSiblingDB("the_homes_ha");
const head = (t) => print("\n" + "=".repeat(70) + "\n" + t + "\n" + "=".repeat(70));

function memberTable() {
  const st = rs.status();
  const prim = st.members.find(m => m.stateStr === "PRIMARY");
  return st.members.map(m => ({
    member: m.name, state: m.stateStr, health: m.health,
    lag_seconds: prim && m.optimeDate ? (prim.optimeDate - m.optimeDate) / 1000 : null
  }));
}

head("R1  Replica set members: one PRIMARY accepts writes, the others are SECONDARY");
printjson(memberTable());

head("R2  Write one review to the PRIMARY and wait until a majority has it (w: majority)");
dbh.reviews.deleteOne({ _id: "HA-DEMO-1" });
printjson(dbh.reviews.insertOne(
  { _id: "HA-DEMO-1", hotel_id: 1, hotel: "The Homes Abuja", guest_id: 100, rating: { overall: 5 },
    comment: "Replication demo review", posted_at: new Date() },
  { writeConcern: { w: "majority", j: true } }));

head("R3  Read the same review DIRECTLY from each member (secondaries need readPreference secondaryPreferred)");
[27018, 27019, 27020].forEach(port => {
  const c = new Mongo(`mongodb://127.0.0.1:${port}/?directConnection=true&readPreference=secondaryPreferred`);
  const col = c.getDB("the_homes_ha").reviews;
  const role = c.getDB("admin").hello().isWritablePrimary ? "PRIMARY  " : "SECONDARY";
  print(`port ${port} ${role} | reviews in collection: ${col.countDocuments()} | demo review found: ${col.findOne({ _id: "HA-DEMO-1" }) !== null}`);
});

head("R4  The oplog entry that carried the write (this is what secondaries replay)");
printjson(db.getSiblingDB("local").oplog.rs
  .find({ ns: "the_homes_ha.reviews", op: "i", "o._id": "HA-DEMO-1" }, { op: 1, ns: 1, ts: 1, "o._id": 1, "o.comment": 1 })
  .sort({ $natural: -1 }).limit(1).toArray());

head("R5  Oplog window: how much history the primary keeps for secondaries that fall behind");
print(rs.printReplicationInfo());

head("R6  Replica set configuration (priorities and votes)");
printjson(rs.conf().members.map(m => ({ host: m.host, priority: m.priority, votes: m.votes })));

dbh.reviews.deleteOne({ _id: "HA-DEMO-1" });
