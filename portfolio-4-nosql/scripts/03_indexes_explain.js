// =====================================================================
// Portfolio 4 | 03_indexes_explain.js   (mongosh)
// Shows the effect of indexes in MongoDB: for each query it prints the
// plan summary BEFORE and AFTER creating an index.
//
//   mongosh "mongodb://localhost:27017/the_homes_nosql" --file scripts/03_indexes_explain.js > results/03_indexes_output.txt
//
// Look for:  COLLSCAN (reads every document)  ->  IXSCAN (uses an index)
// Safe to re-run: indexes are dropped first so the BEFORE state is repeatable.
// =====================================================================
const dbh = db.getSiblingDB("the_homes_nosql");

["guest_profiles", "reviews", "activity_events"].forEach(c => dbh.getCollection(c).dropIndexes());

// Walk down the winning plan and report the stages used
function stages(p, out = []) {
  if (!p) return out;
  out.push(p.stage + (p.indexName ? "(" + p.indexName + ")" : ""));
  if (p.inputStage) stages(p.inputStage, out);
  if (p.inputStages) p.inputStages.forEach(s => stages(s, out));
  return out;
}

function plan(label, coll, filter, sort, limit) {
  let cur = dbh.getCollection(coll).find(filter);
  if (sort) cur = cur.sort(sort);
  if (limit) cur = cur.limit(limit);
  const ex = cur.explain("executionStats");
  const s = ex.executionStats;
  print(`  ${label}`);
  print(`    stages: ${stages(ex.queryPlanner.winningPlan).join(" -> ")}`);
  print(`    documents examined: ${s.totalDocsExamined} | index keys examined: ${s.totalKeysExamined} | returned: ${s.nReturned} | time: ${s.executionTimeMillis} ms`);
}

function experiment(title, coll, filter, sort, limit, indexSpec, indexOpts) {
  print("\n" + "=".repeat(70));
  print(title);
  print("=".repeat(70));
  plan("BEFORE (no index)", coll, filter, sort, limit);
  const name = dbh.getCollection(coll).createIndex(indexSpec, indexOpts || {});
  print("  created index: " + name + "  " + JSON.stringify(indexSpec));
  plan("AFTER", coll, filter, sort, limit);
}

// Pick a real e-mail from the data
const sample = dbh.guest_profiles.findOne({ _id: 12345 });

experiment("I1  Find a guest by e-mail (login / front desk lookup)",
  "guest_profiles", { email: sample.email }, null, null,
  { email: 1 }, { unique: true });

experiment("I2  Latest 10 reviews of one hotel (compound index serves filter AND sort)",
  "reviews", { hotel_id: 3 }, { posted_at: -1 }, 10,
  { hotel_id: 1, posted_at: -1 });

experiment("I3  Reviews tagged 'noise' with rating 2 or lower (multikey index on the tags array)",
  "reviews", { tags: "noise", "rating.overall": { $lte: 2 } }, null, null,
  { tags: 1, "rating.overall": 1 });

experiment("I4  Noise alerts at hotel 1 in the last 30 days (compound index: equality, equality, range)",
  "activity_events",
  { hotel_id: 1, type: "noise_alert", ts: { $gte: new Date(Date.now() - 30 * 24 * 3600 * 1000) } },
  null, null,
  { hotel_id: 1, type: 1, ts: -1 });

experiment("I5  Top-spending Silver, Gold and Platinum members (compound index)",
  "guest_profiles", { "loyalty.tier": { $in: ["Silver", "Gold", "Platinum"] } }, { "stay_summary.total_spend": -1 }, 10,
  { "loyalty.tier": 1, "stay_summary.total_spend": -1 });

// Text index for keyword search (used in 04_queries.js, Q5)
dbh.reviews.createIndex({ title: "text", comment: "text" }, { name: "reviews_text" });
dbh.reviews.createIndex({ guest_id: 1 });   // supports $lookup from guest_profiles (Q9)

print("\n" + "=".repeat(70));
print("Index inventory and sizes (bytes)");
print("=".repeat(70));
["guest_profiles", "reviews", "activity_events"].forEach(c => {
  const st = dbh.getCollection(c).stats();
  print(`${c}: data ${st.size} bytes | total index size ${st.totalIndexSize} bytes`);
  Object.entries(st.indexSizes).forEach(([n, sz]) => print(`   ${n}: ${sz}`));
});
