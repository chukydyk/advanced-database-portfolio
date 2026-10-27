// =====================================================================
// Portfolio 4 | 04_queries.js   (mongosh)
// Eleven queries on the document model of The Homes.
//
//   mongosh "mongodb://localhost:27017/the_homes_nosql" --file scripts/04_queries.js > results/04_queries_output.txt
//
// Run 03_indexes_explain.js first: Q5 needs the text index and Q9 the guest_id index.
// =====================================================================
const dbh = db.getSiblingDB("the_homes_nosql");
const head = (t) => print("\n" + "=".repeat(70) + "\n" + t + "\n" + "=".repeat(70));

// ---------------------------------------------------------------------
head("Q1  One lookup returns a complete guest profile (preferences, summary, recent stays)\n    Relational equivalent: joins across guest, loyalty_account, booking, hotel ...");
printjson(dbh.guest_profiles.findOne(
  { _id: 100 },
  { name: 1, email: 1, loyalty: 1, preferences: 1, stay_summary: 1, recent_stays: { $slice: 2 } }));

// ---------------------------------------------------------------------
head("Q2  Five latest 4-5 star reviews at The Homes Abuja that mention breakfast");
dbh.reviews.find(
  { hotel_id: 1, tags: "breakfast", "rating.overall": { $gte: 4 } },
  { _id: 0, guest_display: 1, posted_at: 1, "rating.overall": 1, title: 1, comment: 1 }
).sort({ posted_at: -1 }).limit(5).forEach(d => printjson(d));

// ---------------------------------------------------------------------
head("Q3  Average rating per category and hotel (rating fields vary: 'food' exists in only some reviews)");
printjson(dbh.reviews.aggregate([
  { $group: { _id: "$hotel",
              reviews: { $sum: 1 },
              overall:     { $avg: "$rating.overall" },
              cleanliness: { $avg: "$rating.cleanliness" },
              service:     { $avg: "$rating.service" },
              value:       { $avg: "$rating.value" },
              food:        { $avg: "$rating.food" },
              food_rated:  { $sum: { $cond: [{ $ifNull: ["$rating.food", false] }, 1, 0] } } } },
  { $project: { reviews: 1, food_rated: 1,
                overall: { $round: ["$overall", 2] }, cleanliness: { $round: ["$cleanliness", 2] },
                service: { $round: ["$service", 2] }, value: { $round: ["$value", 2] },
                food: { $round: ["$food", 2] } } },
  { $sort: { _id: 1 } }
]).toArray());

// ---------------------------------------------------------------------
head("Q4  The three most mentioned topics per hotel, with their average rating");
printjson(dbh.reviews.aggregate([
  { $unwind: "$tags" },
  { $group: { _id: { hotel: "$hotel", tag: "$tags" }, mentions: { $sum: 1 }, avg: { $avg: "$rating.overall" } } },
  { $sort: { "_id.hotel": 1, mentions: -1 } },
  { $group: { _id: "$_id.hotel",
              top: { $push: { tag: "$_id.tag", mentions: "$mentions", avg_rating: { $round: ["$avg", 2] } } } } },
  { $project: { top: { $slice: ["$top", 3] } } },
  { $sort: { _id: 1 } }
]).toArray());

// ---------------------------------------------------------------------
head("Q5  Full-text search: reviews complaining about noise (ranked by relevance)");
dbh.reviews.find(
  { $text: { $search: "noise" }, "rating.overall": { $lte: 2 } },
  { _id: 0, hotel: 1, "rating.overall": 1, comment: 1, score: { $meta: "textScore" } }
).sort({ score: { $meta: "textScore" } }).limit(3).forEach(d => printjson(d));

// ---------------------------------------------------------------------
head("Q6  Rating distribution and recommendation rate in ONE round trip ($facet + $bucket)");
printjson(dbh.reviews.aggregate([
  { $facet: {
      histogram: [ { $bucket: { groupBy: "$rating.overall", boundaries: [1, 2, 3, 4, 5, 6],
                                output: { reviews: { $sum: 1 } } } } ],
      recommend: [ { $group: { _id: null, total: { $sum: 1 },
                               recommended: { $sum: { $cond: ["$would_recommend", 1, 0] } } } },
                   { $project: { _id: 0, total: 1, recommended: 1,
                                 recommend_pct: { $round: [{ $multiply: [{ $divide: ["$recommended", "$total"] }, 100] }, 1] } } } ]
  } }
]).toArray());

// ---------------------------------------------------------------------
head("Q7  Event log: how many events of each type per hotel (payload differs by type)");
printjson(dbh.activity_events.aggregate([
  { $group: { _id: { hotel_id: "$hotel_id", type: "$type" }, events: { $sum: 1 } } },
  { $sort: { "_id.hotel_id": 1, events: -1 } },
  { $group: { _id: "$_id.hotel_id", by_type: { $push: { type: "$_id.type", events: "$events" } } } },
  { $sort: { _id: 1 } }
]).toArray());

// ---------------------------------------------------------------------
head("Q8  Five rooms with the most noise alerts, with their average decibel level");
printjson(dbh.activity_events.aggregate([
  { $match: { type: "noise_alert" } },
  { $group: { _id: { hotel_id: "$hotel_id", room_id: "$payload.room_id" },
              alerts: { $sum: 1 }, avg_db: { $avg: "$payload.decibels" } } },
  { $sort: { alerts: -1, "_id.room_id": 1 } },
  { $limit: 5 },
  { $project: { _id: 0, hotel_id: "$_id.hotel_id", room_id: "$_id.room_id", alerts: 1, avg_db: { $round: ["$avg_db", 1] } } }
]).toArray());

// ---------------------------------------------------------------------
head("Q9  $lookup (a join): loyalty members with their review count and average rating");
printjson(dbh.guest_profiles.aggregate([
  { $match: { "loyalty.tier": { $in: ["Silver", "Gold", "Platinum"] } } },
  { $lookup: { from: "reviews", localField: "_id", foreignField: "guest_id", as: "my_reviews" } },
  { $project: { _id: 1, name: 1, tier: "$loyalty.tier", stays: "$stay_summary.completed_stays",
                reviews_written: { $size: "$my_reviews" },
                avg_rating: { $round: [{ $avg: "$my_reviews.rating.overall" }, 2] } } },
  { $sort: { reviews_written: -1, _id: 1 } },
  { $limit: 5 }
]).toArray());

// ---------------------------------------------------------------------
head("Q10 Schema flexibility: which preference fields do guests actually have?");
printjson(dbh.guest_profiles.aggregate([
  { $project: { keys: { $map: { input: { $objectToArray: "$preferences" }, as: "kv", in: "$$kv.k" } } } },
  { $unwind: "$keys" },
  { $group: { _id: "$keys", guests: { $sum: 1 } } },
  { $sort: { guests: -1 } }
]).toArray());
print("Vegetarian guests:", dbh.guest_profiles.countDocuments({ "preferences.dining": "vegetarian" }));
print("Guests wanting a late checkout:", dbh.guest_profiles.countDocuments({ "preferences.late_checkout": true }));

// ---------------------------------------------------------------------
head("Q11 Hotel document: rooms embedded, so one read answers 'what does this hotel offer?'");
printjson(dbh.hotels.aggregate([
  { $project: { name: 1, city: 1, rooms_total: { $size: "$rooms" },
                suites: { $size: { $filter: { input: "$rooms", as: "r", cond: { $eq: ["$$r.type", "Suite"] } } } },
                services: "$services.name" } },
  { $sort: { _id: 1 } }
]).toArray());
printjson(dbh.hotels.findOne({ _id: 1 }, { name: 1, rooms: { $slice: 1 } }));
