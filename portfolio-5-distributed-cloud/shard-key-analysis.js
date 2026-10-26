// =============================================================
// NairaFlow – Portfolio 5: shard-key analysis on the real transaction events
// Simulates splitting transaction_events across THREE shards using three
// candidate shard keys, and measures (a) how evenly ALL documents spread and
// (b) where the NEWEST 5,000 writes land (the insert hot spot).
// Run in mongosh after `use("nairaflow")`. Read-only: nothing is changed.
// =============================================================
use("nairaflow");

(function shardKeyAnalysis() {
  const c = db.transaction_events;
  const realOnly = { _id: { $lt: 900000 } };      // exclude Portfolio 5 test events

  const first = c.find(realOnly, { createdAt: 1 }).sort({ createdAt: 1 }).limit(1).next().createdAt;
  const last  = c.find(realOnly, { createdAt: 1 }).sort({ createdAt: -1 }).limit(1).next().createdAt;
  const span  = last.getTime() - first.getTime();
  const cut1  = new Date(first.getTime() + span / 3);
  const cut2  = new Date(first.getTime() + 2 * span / 3);
  const newestFrom = c.find(realOnly, { createdAt: 1 }).sort({ createdAt: -1 })
                      .skip(4999).limit(1).next().createdAt;

  const shards = ["shard A", "shard B", "shard C"];
  const candidates = {
    "range on createdAt": { $switch: { branches: [
        { case: { $lt: ["$createdAt", cut1] }, then: "shard A" },
        { case: { $lt: ["$createdAt", cut2] }, then: "shard B" } ], default: "shard C" } },
    "range on accountId": { $switch: { branches: [
        { case: { $lte: ["$acct", 667] },  then: "shard A" },
        { case: { $lte: ["$acct", 1334] }, then: "shard B" } ], default: "shard C" } },
    "hashed accountId": { $arrayElemAt: [ shards,
        { $toInt: { $mod: [ { $abs: { $toHashedIndexKey: "$acct" } }, 3 ] } } ] }
  };

  const report = [];
  for (const [key, expr] of Object.entries(candidates)) {
    const rows = c.aggregate([
      { $match: realOnly },
      { $project: { createdAt: 1,
          acct: { $ifNull: ["$transfer.fromAccount", { $arrayElemAt: ["$ledger.accountId", 0] }] } } },
      { $addFields: { shard: expr } },
      { $group: { _id: "$shard",
                  allDocs: { $sum: 1 },
                  newest5000: { $sum: { $cond: [{ $gte: ["$createdAt", newestFrom] }, 1, 0] } } } },
      { $sort: { _id: 1 } }
    ]).toArray();
    const total  = rows.reduce((s, r) => s + r.allDocs, 0);
    const newest = rows.reduce((s, r) => s + r.newest5000, 0);
    const row = { shardKey: key };
    for (const s of shards) {
      const r = rows.find(x => x._id === s) || { allDocs: 0, newest5000: 0 };
      row[s + " (all %)"]    = (100 * r.allDocs / total).toFixed(1);
      row[s + " (newest %)"] = (100 * r.newest5000 / newest).toFixed(1);
    }
    report.push(row);
  }
  print("Documents analysed: " + c.countDocuments(realOnly) +
        " | newest-5,000 window starts " + newestFrom.toISOString());
  printjson(report);
})();
// Interpretation:
//  - range on createdAt: data spreads by time, but ~100% of NEW writes hit the last shard (hot shard).
//  - range on accountId: even only if account numbers are evenly active; new accounts all land on the last range.
//  - hashed accountId: ~33% everywhere, for both stored data and new writes.
