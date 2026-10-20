// =============================================================
// NairaFlow – MongoDB queries (run ONE block at a time in mongosh)
// MIT 8103 Portfolio 4: NoSQL and Advanced Data Models
// =============================================================
use("nairaflow");


// D1. CUSTOMER PROFILE IN ONE READ
// Find the customer who owns account 9000000001: profile, KYC and all
// accounts come back as ONE document. No joins (PostgreSQL needs 4 tables).
db.customers.findOne({ "accounts.accountNumber": "9000000001" });

// D1 explain: proves the multikey index on accounts.accountNumber is used
db.customers.find({ "accounts.accountNumber": "9000000001" })
  .explain("executionStats").executionStats;


// D2. ACCOUNT STATEMENT: account 2001's activity since 1 October 2026
// $elemMatch in the projection returns only account 2001's ledger line.
db.transaction_events.find(
  { "ledger.accountId": 2001, createdAt: { $gte: ISODate("2026-10-01") } },
  { reference: 1, type: 1, amount: 1, status: 1, createdAt: 1,
    ledger: { $elemMatch: { accountId: 2001 } } }
).sort({ createdAt: -1 });

// D2 explain WITH the index
db.transaction_events.find(
  { "ledger.accountId": 2001, createdAt: { $gte: ISODate("2026-10-01") } }
).sort({ createdAt: -1 }).explain("executionStats").executionStats;

// D2 explain WITHOUT the index (forced full collection scan, for comparison)
db.transaction_events.find(
  { "ledger.accountId": 2001, createdAt: { $gte: ISODate("2026-10-01") } }
).sort({ createdAt: -1 }).hint({ $natural: 1 }).explain("executionStats").executionStats;


// D3. AGGREGATION PIPELINE: daily totals by type for September 2026
// (MongoDB version of Portfolio 2's Q4; results should match PostgreSQL exactly)
db.transaction_events.aggregate([
  { $match: { status: "SUCCESS",
              createdAt: { $gte: ISODate("2026-09-01"), $lt: ISODate("2026-10-01") } } },
  { $group: { _id: { day:  { $dateToString: { format: "%Y-%m-%d", date: "$createdAt" } },
                     type: "$type" },
              count: { $sum: 1 },
              total: { $sum: "$amount" } } },
  { $sort: { "_id.day": 1, "_id.type": 1 } },
  { $limit: 6 }
]);


// D4. GRAPH TRAVERSAL: detect circular high-value money flows (money-mule ring)
// For every successful transfer of ₦50,000+, follow the money onward
// (to-account -> transfers OUT of that account) up to 4 hops, then flag
// chains that return to the account where they started.
db.transaction_events.aggregate([
  { $match: { type: "TRANSFER", status: "SUCCESS",
              amount: { $gte: NumberDecimal("50000") } } },
  { $graphLookup: {
      from: "transaction_events",
      startWith: "$transfer.toAccount",
      connectFromField: "transfer.toAccount",
      connectToField: "transfer.fromAccount",
      as: "chain",
      maxDepth: 4,
      depthField: "hop",
      restrictSearchWithMatch: { type: "TRANSFER", status: "SUCCESS",
                                 amount: { $gte: NumberDecimal("50000") } }
  } },
  { $project: {
      _id: 0,
      startAccount: "$transfer.fromAccount",
      firstTransfer: { to: "$transfer.toAccount", amount: "$amount", reference: "$reference" },
      chain: { $map: {
        input: { $sortArray: { input: "$chain", sortBy: { hop: 1 } } },
        as: "c",
        in: { hop: "$$c.hop", from: "$$c.transfer.fromAccount",
              to: "$$c.transfer.toAccount", amount: "$$c.amount" } } }
  } },
  { $addFields: { returnsToStart: { $in: ["$startAccount", "$chain.to"] } } },
  { $match: { returnsToStart: true } }
]);


// D5. SCHEMA FLEXIBILITY: add a new optional field to ONE customer,
// with no schema migration (PostgreSQL would need ALTER TABLE for every row)
db.customers.updateOne(
  { _id: 1001 },
  { $set: { trustedDevices: [
      { deviceId: "a1b2c3", platform: "Android", firstSeen: new Date() },
      { deviceId: "d4e5f6", platform: "Web",     firstSeen: new Date() } ] } }
);
db.customers.findOne({ _id: 1001 }, { name: 1, trustedDevices: 1 });