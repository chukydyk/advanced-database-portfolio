// =====================================================================
// Portfolio 5 | shard_03_configure.js   (mongosh, connect to the mongos router)
//   mongosh "mongodb://127.0.0.1:27200" --file scripts/shard_03_configure.js
//
// Shard key decisions for The Homes:
//  activity_events : compound key { hotel_id, ts } plus ZONES, so each country's
//                    hotels live on "their" shard (data locality and residency).
//  guest_profiles  : hashed _id, because guests are looked up by id and have no
//                    natural geographic key: hashing spreads them evenly.
// =====================================================================
const head = (t) => print("\n" + "=".repeat(70) + "\n" + t + "\n" + "=".repeat(70));
const DB = "the_homes_shard";

head("H1  Enable sharding and assign zones to shards");
printjson(sh.enableSharding(DB));
sh.addShardToZone("shard1rs", "NIGERIA");          // shard 1 holds the Nigerian hotels
sh.addShardToZone("shard2rs", "REST_OF_AFRICA");   // shard 2 holds Ghana and Kenya
print("Zone NIGERIA -> shard1rs, zone REST_OF_AFRICA -> shard2rs");

head("H2  Shard activity_events on { hotel_id: 1, ts: 1 } and map hotels to zones");
const ev = DB + ".activity_events";
printjson(sh.shardCollection(ev, { hotel_id: 1, ts: 1 }));
// hotels 1, 2, 3 (Abuja, Lagos, Port Harcourt) -> Nigeria. Hotels 4, 5 (Accra, Nairobi) -> rest of Africa
sh.updateZoneKeyRange(ev, { hotel_id: MinKey, ts: MinKey }, { hotel_id: 4, ts: MinKey }, "NIGERIA");
sh.updateZoneKeyRange(ev, { hotel_id: 4, ts: MinKey }, { hotel_id: MaxKey, ts: MaxKey }, "REST_OF_AFRICA");
print("Zone ranges defined for activity_events");

head("H3  Shard guest_profiles on a HASHED _id");
printjson(sh.shardCollection(DB + ".guest_profiles", { _id: "hashed" }));

head("H4  Give the balancer a moment to place the empty chunks, then show the chunk map");
sleep(8000);
const cfg = db.getSiblingDB("config");
[ev, DB + ".guest_profiles"].forEach(ns => {
  const c = cfg.collections.findOne({ _id: ns });
  print("\n" + ns + "  shard key: " + JSON.stringify(c.key));
  printjson(cfg.chunks.aggregate([{ $match: { uuid: c.uuid } }, { $group: { _id: "$shard", chunks: { $sum: 1 } } }, { $sort: { _id: 1 } }]).toArray());
});
