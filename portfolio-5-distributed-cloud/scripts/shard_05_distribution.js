// =====================================================================
// Portfolio 5 | shard_05_distribution.js   (mongosh, connect to the mongos router)
//   mongosh "mongodb://127.0.0.1:27200" --file scripts/shard_05_distribution.js > results/shard_distribution_output.txt
// Shows how the data is spread, which hotels live on which shard, and which
// queries are routed to one shard (targeted) or to all shards (scatter-gather).
// =====================================================================
const dbh = db.getSiblingDB("the_homes_shard");
const head = (t) => print("\n" + "=".repeat(70) + "\n" + t + "\n" + "=".repeat(70));

head("D1  Documents per shard");
["activity_events", "guest_profiles"].forEach(name => {
  const parts = dbh.getCollection(name).aggregate([{ $collStats: { storageStats: {} } }]).toArray();
  const total = parts.reduce((a, p) => a + p.storageStats.count, 0);
  print("\n" + name + " (" + total + " documents)");
  parts.sort((a, b) => a.shard.localeCompare(b.shard)).forEach(p =>
    print(`  ${p.shard}: ${String(p.storageStats.count).padStart(7)} documents (${(100 * p.storageStats.count / total).toFixed(1)}%)`));
});

head("D2  Which hotels are stored on which shard? (asking each shard directly)");
[["shard1rs", 27102], ["shard2rs", 27103]].forEach(([name, port]) => {
  const c = new Mongo(`mongodb://127.0.0.1:${port}/?directConnection=true`);
  const rows = c.getDB("the_homes_shard").activity_events.aggregate([
    { $group: { _id: "$hotel_id", events: { $sum: 1 } } }, { $sort: { _id: 1 } }]).toArray();
  print(`${name}: ` + rows.map(r => `hotel ${r._id} (${r.events})`).join(", "));
});

head("D3  Chunk count per shard");
const cfg = db.getSiblingDB("config");
["the_homes_shard.activity_events", "the_homes_shard.guest_profiles"].forEach(ns => {
  const c = cfg.collections.findOne({ _id: ns });
  print(ns + "  key " + JSON.stringify(c.key));
  cfg.chunks.aggregate([{ $match: { uuid: c.uuid } }, { $group: { _id: "$shard", chunks: { $sum: 1 } } }, { $sort: { _id: 1 } }])
     .forEach(r => print("   " + r._id + ": " + r.chunks + " chunks"));
});

head("D4  Query routing: targeted (one shard) versus scatter-gather (every shard)");
function route(label, cursor) {
  const w = cursor.explain().queryPlanner.winningPlan;
  const shards = (w.shards || []).map(s => s.shardName);
  print(`${label.padEnd(58)} -> ${String(w.stage).padEnd(12)} shards: ${shards.join(", ")}`);
}
route("events WHERE hotel_id = 2 AND ts >= Sep 2026 (key prefix)", dbh.activity_events.find({ hotel_id: 2, ts: { $gte: new Date("2026-09-01") } }));
route("events WHERE hotel_id IN (1, 5) (hotels in both zones)", dbh.activity_events.find({ hotel_id: { $in: [1, 5] } }));
route("events WHERE type = 'noise_alert' (no shard key)", dbh.activity_events.find({ type: "noise_alert" }));
route("guest_profiles WHERE _id = 100 (hashed key, equality)", dbh.guest_profiles.find({ _id: 100 }));
route("guest_profiles WHERE email = ... (no shard key)", dbh.guest_profiles.find({ email: "someone@example.com" }));
route("guest_profiles WHERE _id between 1 and 50 (hashed key, range)", dbh.guest_profiles.find({ _id: { $gte: 1, $lte: 50 } }));
print("\nTargeted queries touch one shard and scale with the cluster. Scatter-gather queries touch every shard,");
print("so the shard key must match the main access pattern. Range queries on a hashed key cannot be targeted.");
