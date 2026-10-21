// =============================================================
// NairaFlow – Portfolio 5: replication tests on MongoDB Atlas
// Three-node replica set (AWS eu-west-3). Run ONE block at a time in mongosh.
// =============================================================
use("nairaflow");


// ---------- PART A: replica set summary ----------
const h = db.hello();
({ replicaSet: h.setName, members: h.hosts, primary: h.primary,
   connectedTo: h.me, isPrimary: h.isWritablePrimary });


// ---------- PART B: read preferences ----------
// B1. Default read preference (primary): which server answered?
db.getMongo().setReadPref("primary");
db.customers.find({ _id: 1001 }).explain().serverInfo;

// B2. Read from a SECONDARY: which server answered now?
db.getMongo().setReadPref("secondary");
db.customers.find({ _id: 1001 }).explain().serverInfo;

// B3. Reset to primary (important: later writes and tests assume primary)
db.getMongo().setReadPref("primary");


// ---------- PART C: write concerns ----------
// C1. Time 15 inserts at each write concern and report the median.
function timeInserts(label, writeConcern, n) {
  const times = [];
  for (let i = 0; i < n; i++) {
    const t0 = Date.now();
    db.replication_tests.insertOne({ label, i, at: new Date() }, { writeConcern });
    times.push(Date.now() - t0);
  }
  times.sort((a, b) => a - b);
  return { label, runs: n, medianMs: times[Math.floor(n / 2)],
           minMs: times[0], maxMs: times[n - 1] };
}
[
  timeInserts("w:1 (primary only)",       { w: 1 },          15),
  timeInserts("w:majority (2 of 3)",      { w: "majority" }, 15),
  timeInserts("w:3 (all three servers)",  { w: 3 },          15)
];

// C2. Ask for more confirmations than there are servers: must fail.
db.replication_tests.insertOne(
  { label: "w:5 test", at: new Date() },
  { writeConcern: { w: 5, wtimeout: 5000 } }
);

// C3. Majority read: only return data that a majority of servers have confirmed.
db.customers.find({ _id: 1001 }, { name: 1 }).readConcern("majority");

// C4. Clean up the test collection.
db.replication_tests.drop();