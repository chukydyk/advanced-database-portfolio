// =====================================================================
// Portfolio 4 | graph/cypher_examples.cypher   (OPTIONAL, DESIGN SKETCH)
// A graph model of The Homes in Neo4j's Cypher language.
// STATUS: design only. These statements were NOT executed for this
// portfolio. If you run them (for example in a free Neo4j Aura instance or
// Neo4j Desktop), keep the screenshots and describe the results yourself.
// =====================================================================

// ---- Model -----------------------------------------------------------
// (:Guest)-[:STAYED_AT {nights, year}]->(:Hotel)
// (:Guest)-[:REFERRED]->(:Guest)
// (:Guest)-[:BOOKED_VIA]->(:Channel)
// (:Guest)-[:REVIEWED {rating}]->(:Hotel)

// ---- Sample data -----------------------------------------------------
CREATE (h1:Hotel {id: 1, name: 'The Homes Abuja'}),
       (h2:Hotel {id: 2, name: 'The Homes Lagos'}),
       (h3:Hotel {id: 3, name: 'The Homes Accra'}),
       (g1:Guest {id: 1, name: 'Ibrahim Hassan'}),
       (g2:Guest {id: 2, name: 'Amina Martin'}),
       (g3:Guest {id: 3, name: 'Musa Danjuma'}),
       (g4:Guest {id: 4, name: 'Ngozi Eze'}),
       (g1)-[:STAYED_AT {nights: 6, year: 2025}]->(h1),
       (g1)-[:STAYED_AT {nights: 3, year: 2026}]->(h2),
       (g2)-[:STAYED_AT {nights: 4, year: 2025}]->(h1),
       (g2)-[:STAYED_AT {nights: 2, year: 2026}]->(h3),
       (g3)-[:STAYED_AT {nights: 5, year: 2026}]->(h2),
       (g4)-[:STAYED_AT {nights: 2, year: 2026}]->(h3),
       (g1)-[:REFERRED]->(g2),
       (g2)-[:REFERRED]->(g3),
       (g3)-[:REFERRED]->(g4);

// ---- Questions a graph answers naturally -------------------------------
// G1  Recommend hotels: where did guests who stayed with Ibrahim also stay?
MATCH (me:Guest {id: 1})-[:STAYED_AT]->(h:Hotel)<-[:STAYED_AT]-(other:Guest)-[:STAYED_AT]->(rec:Hotel)
WHERE NOT (me)-[:STAYED_AT]->(rec)
RETURN rec.name AS recommended_hotel, count(DISTINCT other) AS similar_guests
ORDER BY similar_guests DESC;

// G2  Referral chain: everyone Ibrahim brought in, directly or indirectly
MATCH path = (:Guest {id: 1})-[:REFERRED*1..4]->(referred:Guest)
RETURN referred.name AS guest, length(path) AS referral_depth
ORDER BY referral_depth;

// G3  Shortest connection between two guests
MATCH p = shortestPath((a:Guest {id: 1})-[:REFERRED*]-(b:Guest {id: 4}))
RETURN [n IN nodes(p) | n.name] AS chain, length(p) AS hops;

// G4  Which hotel pairs share the most guests (cross-selling)?
MATCH (a:Hotel)<-[:STAYED_AT]-(g:Guest)-[:STAYED_AT]->(b:Hotel)
WHERE a.id < b.id
RETURN a.name, b.name, count(DISTINCT g) AS shared_guests
ORDER BY shared_guests DESC;
