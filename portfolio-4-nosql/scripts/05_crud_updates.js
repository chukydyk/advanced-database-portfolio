// =====================================================================
// Portfolio 4 | 05_crud_updates.js   (mongosh)
// Create, read, update and delete operations, schema validation in action,
// and single-document atomicity.
//
//   mongosh "mongodb://localhost:27017/the_homes_nosql" --file scripts/05_crud_updates.js > results/05_crud_output.txt
//
// Test documents use _id values 900000001 and above and are removed at the end.
// =====================================================================
const dbh = db.getSiblingDB("the_homes_nosql");
const head = (t) => print("\n" + "=".repeat(70) + "\n" + t + "\n" + "=".repeat(70));

// Clean up any leftovers from an earlier run
dbh.reviews.deleteMany({ _id: { $gte: 900000001 } });

// ---------------------------------------------------------------------
head("C1  INSERT a valid review");
const ok = dbh.reviews.insertOne({
  _id: 900000001, booking_id: 900000001, hotel_id: 1, hotel: "The Homes Abuja",
  guest_id: 100, guest_display: "Kamau N.", room_type: "Deluxe",
  posted_at: new Date(), rating: { overall: 5, cleanliness: 5, service: 4 },
  title: "Superb weekend", comment: "Spotless room and a very friendly front desk.",
  tags: ["cleanliness", "staff"], would_recommend: true, helpful_votes: 0
});
printjson(ok);

// ---------------------------------------------------------------------
head("C2  INSERT an INVALID review: schema validation rejects it (rating 9, no comment)");
try {
  dbh.reviews.insertOne({
    _id: 900000002, booking_id: 900000002, hotel_id: 1, guest_id: 100,
    posted_at: new Date(), rating: { overall: 9 }
  });
  print("Unexpected: the invalid document was accepted");
} catch (e) {
  print("Rejected as expected:", e.codeName || e.message);
  print("Error code:", e.code, "| message:", e.errmsg || e.message);
}

// ---------------------------------------------------------------------
head("C3  READ it back");
printjson(dbh.reviews.findOne({ _id: 900000001 }, { _id: 1, hotel: 1, rating: 1, title: 1, helpful_votes: 1 }));

// ---------------------------------------------------------------------
head("C4  UPDATE: add a hotel response and increase helpful_votes in ONE atomic operation");
printjson(dbh.reviews.updateOne(
  { _id: 900000001 },
  { $set: { hotel_response: { responded_at: new Date(), by: "Guest Relations", text: "Thank you, we hope to see you again soon." } },
    $inc: { helpful_votes: 1 },
    $addToSet: { tags: "front desk" } }));
printjson(dbh.reviews.findOne({ _id: 900000001 }, { hotel_response: 1, helpful_votes: 1, tags: 1 }));

// ---------------------------------------------------------------------
head("C5  UPDATE a guest profile: add a new preference field (no schema migration needed)");
const before = dbh.guest_profiles.findOne({ _id: 7 }, { preferences: 1 });
print("Before:", JSON.stringify(before.preferences));
dbh.guest_profiles.updateOne({ _id: 7 }, { $set: { "preferences.quiet_hours": { from: "22:00", to: "07:00" } },
                                           $addToSet: { "preferences.dining": "vegetarian" } });
print("After: ", JSON.stringify(dbh.guest_profiles.findOne({ _id: 7 }, { preferences: 1 }).preferences));
// restore the original document so the dataset is unchanged
dbh.guest_profiles.updateOne({ _id: 7 }, { $set: { preferences: before.preferences } });

// ---------------------------------------------------------------------
head("C6  Single-document atomicity: each $inc is applied atomically (20 increments, none lost)");
dbh.reviews.updateOne({ _id: 900000001 }, { $set: { helpful_votes: 0 } });
for (let i = 0; i < 20; i++) dbh.reviews.updateOne({ _id: 900000001 }, { $inc: { helpful_votes: 1 } });
print("helpful_votes after 20 increments:", dbh.reviews.findOne({ _id: 900000001 }).helpful_votes);
print("(Each $inc is applied atomically by the server, so no read-modify-write race as in Portfolio 3 D1a.)");

// ---------------------------------------------------------------------
head("C7  DELETE the test review");
printjson(dbh.reviews.deleteOne({ _id: 900000001 }));
print("Test reviews remaining:", dbh.reviews.countDocuments({ _id: { $gte: 900000001 } }));
