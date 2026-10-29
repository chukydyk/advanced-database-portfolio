// =====================================================================
// Portfolio 5 | failover_writer.js   (mongosh, started by rs_04_failover_test.sh)
// Plays the part of the booking application: it keeps inserting numbered
// records with w: majority while the primary is stopped, retries after
// errors, and reports how long writes were blocked and whether any
// acknowledged write was lost.
// =====================================================================
const uri = process.env.HOMES_URI;
const seconds = Number(process.env.WRITER_SECONDS || 40);
const col = new Mongo(uri).getDB("the_homes_ha").getCollection("failover_test");
col.drop();
col.createIndex({ seq: 1 }, { unique: true });

const t0 = Date.now();
const rel = () => ((Date.now() - t0) / 1000).toFixed(1).padStart(5) + "s";
let seq = 0, acked = 0, errors = 0, maxLatency = 0, maxLatencyAt = 0;

while (Date.now() - t0 < seconds * 1000) {
  seq++;
  const start = Date.now();
  let done = false;
  while (!done) {
    try {
      col.insertOne({ seq: seq, at: new Date() }, { writeConcern: { w: "majority", wtimeout: 5000 } });
      done = true;
    } catch (e) {
      if (e.code === 11000) { done = true; }                 // the earlier attempt was applied: count it once
      else { errors++; print(`[${rel()}] write ${seq} failed (${e.codeName || e.name}): ${String(e.message).slice(0, 90)}`); sleep(300); }
    }
  }
  acked++;
  const lat = Date.now() - start;
  if (lat > maxLatency) { maxLatency = lat; maxLatencyAt = Date.now() - t0; }
  if (lat > 1000) print(`[${rel()}] write ${seq} was blocked for ${(lat / 1000).toFixed(1)} s (election in progress)`);
  sleep(100);
}
print(`WRITER_SUMMARY acknowledged=${acked} errors_seen=${errors} slowest_write_ms=${maxLatency} at=${(maxLatencyAt / 1000).toFixed(1)}s`);
print(`ACKED=${acked}`);
