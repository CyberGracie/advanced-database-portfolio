// =============================================================
// NairaFlow – MongoDB indexes, each matching a query in Part D
// =============================================================
use("nairaflow");

// Customers: unique identifiers and lookup by account number
db.customers.createIndex({ email: 1 }, { unique: true });
db.customers.createIndex({ bvn: 1 },   { unique: true });
db.customers.createIndex({ "accounts.accountNumber": 1 }, { unique: true });   // multikey index on an array

// Transaction events: account statements, failed-transfer monitoring, money-flow tracing
db.transaction_events.createIndex({ "ledger.accountId": 1, createdAt: -1 });  // account statement
db.transaction_events.createIndex({ status: 1, createdAt: -1 });              // failed transfers
db.transaction_events.createIndex({ "transfer.fromAccount": 1 });             // graph traversal

db.customers.getIndexes();
db.transaction_events.getIndexes();