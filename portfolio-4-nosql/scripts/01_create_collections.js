// =====================================================================
// Portfolio 4 | 01_create_collections.js   (mongosh)
// Creates the four collections of the document model WITH schema validation.
// Run BEFORE importing the data (importing with --drop would remove the rules).
//
//   mongosh "mongodb://localhost:27017/the_homes_nosql" --file scripts/01_create_collections.js
// =====================================================================
const dbh = db.getSiblingDB("the_homes_nosql");
print("Database:", dbh.getName());

["hotels", "guest_profiles", "reviews", "activity_events"].forEach(c => dbh.getCollection(c).drop());

// ---------------------------------------------------------------------
// hotels: one document per hotel, rooms and services embedded
// ---------------------------------------------------------------------
dbh.createCollection("hotels", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["_id", "name", "city", "country", "rooms"],
    properties: {
      name:        { bsonType: "string" },
      star_rating: { bsonType: "number", minimum: 1, maximum: 5 },
      rooms:       { bsonType: "array", minItems: 1,
                     items: { bsonType: "object", required: ["room_id", "number", "type"] } }
    }
  }}
});

// ---------------------------------------------------------------------
// guest_profiles: flexible preferences, embedded recent stays
// ---------------------------------------------------------------------
dbh.createCollection("guest_profiles", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["_id", "name", "email", "stay_summary"],
    properties: {
      name:  { bsonType: "object", required: ["first", "last"] },
      email: { bsonType: "string", pattern: "^.+@.+$" },
      loyalty: { bsonType: "object",
                 properties: { tier: { enum: ["Standard", "Silver", "Gold", "Platinum"] },
                               points: { bsonType: "number", minimum: 0 } } },
      stay_summary: { bsonType: "object", required: ["completed_stays", "total_spend"],
                      properties: { completed_stays: { bsonType: "number", minimum: 0 },
                                    total_spend:     { bsonType: "number", minimum: 0 } } },
      recent_stays: { bsonType: "array", maxItems: 5 }
    }
  }}
});

// ---------------------------------------------------------------------
// reviews: rating categories vary, so only "overall" is mandatory
// ---------------------------------------------------------------------
dbh.createCollection("reviews", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["booking_id", "hotel_id", "guest_id", "rating", "posted_at", "comment"],
    properties: {
      hotel_id: { bsonType: "number" },
      guest_id: { bsonType: "number" },
      posted_at: { bsonType: "date" },
      comment: { bsonType: "string", minLength: 5 },
      tags: { bsonType: "array", items: { bsonType: "string" } },
      rating: { bsonType: "object", required: ["overall"],
                properties: { overall:     { bsonType: "number", minimum: 1, maximum: 5 },
                              cleanliness: { bsonType: "number", minimum: 1, maximum: 5 },
                              service:     { bsonType: "number", minimum: 1, maximum: 5 },
                              location:    { bsonType: "number", minimum: 1, maximum: 5 },
                              value:       { bsonType: "number", minimum: 1, maximum: 5 },
                              food:        { bsonType: "number", minimum: 1, maximum: 5 } } }
    }
  }}
});

// ---------------------------------------------------------------------
// activity_events: deliberately light validation (payload differs by type)
// ---------------------------------------------------------------------
dbh.createCollection("activity_events", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["ts", "hotel_id", "type", "payload"],
    properties: {
      ts:      { bsonType: "date" },
      hotel_id: { bsonType: "number" },
      type:    { enum: ["booking_created", "check_in", "door_unlock", "thermostat_set", "noise_alert"] },
      source:  { enum: ["pms", "iot", "app"] },
      payload: { bsonType: "object" }
    }
  }}
});

print("\nCollections created with validation rules:");
dbh.getCollectionInfos().forEach(c => print(" -", c.name, "| validation level:", c.options.validationLevel || "strict (default)"));
