// Portfolio 5 | rs_02_initiate.js (mongosh)
// Turns the three servers into one replica set. All members have equal priority,
// so whichever node wins an election stays primary until something fails.
const cfg = {
  _id: "homesrs",
  members: [
    { _id: 0, host: "127.0.0.1:27018", priority: 1 },
    { _id: 1, host: "127.0.0.1:27019", priority: 1 },
    { _id: 2, host: "127.0.0.1:27020", priority: 1 }
  ]
};
printjson(rs.initiate(cfg));
let tries = 0;
while (!db.hello().isWritablePrimary && tries++ < 60) sleep(1000);
print("Primary is:", db.hello().primary);
