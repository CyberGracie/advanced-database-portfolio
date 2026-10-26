// =============================================================
// NairaFlow – Portfolio 5: multi-document ACID transaction on MongoDB Atlas
// A transfer touches TWO customer documents (debit one account, credit
// another) and inserts ONE transaction event. All three writes must
// succeed together or not at all, across a three-node replica set.
// Run ONE block at a time in mongosh (Compass > Open MongoDB shell).
// Accounts 1 and 2 belong to different customers (customer 1 and 2),
// so this is a genuine multi-document transaction.
// Note: MongoDB balances are an export snapshot; PostgreSQL remains the
// system of record. These test writes change the MongoDB copy only.
// =============================================================
use("nairaflow");


// ---------- Block 1: helpers ----------
function balanceOf(database, acct) {
  const d = database.customers.findOne({ "accounts.accountId": acct },
                                       { _id: 1, "accounts.$": 1 });
  return d ? { customer: d._id, accountId: acct, balance: d.accounts[0].balance } : null;
}

function showBalances(label) {
  print("---- " + label + " ----");
  printjson([balanceOf(db, 1), balanceOf(db, 2)]);
}

function transferInMongo(eventId, fromAcct, toAcct, amount) {
  const session = db.getMongo().startSession();
  const sdb = session.getDatabase("nairaflow");
  const amt = NumberDecimal(amount);
  session.startTransaction({ readConcern: { level: "snapshot" },
                             writeConcern: { w: "majority" } });
  try {
    // 1. Debit only if the balance covers the amount
    const debit = sdb.customers.updateOne(
      { accounts: { $elemMatch: { accountId: fromAcct, balance: { $gte: amt } } } },
      { $inc: { "accounts.$.balance": NumberDecimal("-" + amount) } });
    if (debit.modifiedCount !== 1)
      throw new Error("Insufficient funds or account " + fromAcct + " not found");

    // 2. Credit the destination account (a different customer document)
    const credit = sdb.customers.updateOne(
      { "accounts.accountId": toAcct },
      { $inc: { "accounts.$.balance": amt } });
    if (credit.modifiedCount !== 1)
      throw new Error("Account " + toAcct + " not found");

    // 3. Record the event with both ledger lines
    sdb.transaction_events.insertOne({
      _id: eventId,
      reference: "MONGO-TXN-" + eventId,
      type: "TRANSFER", amount: amt, status: "SUCCESS",
      createdAt: new Date(), completedAt: new Date(),
      transfer: { fromAccount: fromAcct, toAccount: toAcct,
                  idempotencyKey: "MONGO-TXN-" + eventId },
      ledger: [ { accountId: fromAcct, entry: "DEBIT",  amount: amt },
                { accountId: toAcct,   entry: "CREDIT", amount: amt } ]
    });

    session.commitTransaction();
    print("COMMITTED: event " + eventId + " moved " + amount + " from " + fromAcct + " to " + toAcct);
  } catch (e) {
    session.abortTransaction();
    print("ABORTED: " + e.message + " (no document was changed)");
  } finally {
    session.endSession();
  }
}


// ---------- Block 2: T1 – successful transfer (COMMIT) ----------
showBalances("Before T1");
transferInMongo(900001, 1, 2, "1000.00");
showBalances("After T1");
db.transaction_events.findOne({ _id: 900001 });


// ---------- Block 3: T2 – transfer larger than the balance (ABORT) ----------
showBalances("Before T2");
transferInMongo(900002, 1, 2, "999999999.00");
showBalances("After T2 (must be unchanged)");
db.transaction_events.countDocuments({ _id: 900002 });   // must be 0


// ---------- Block 4: T3 – isolation: uncommitted changes are invisible ----------
(function isolationDemo() {
  const session = db.getMongo().startSession();
  const sdb = session.getDatabase("nairaflow");
  session.startTransaction({ readConcern: { level: "snapshot" },
                             writeConcern: { w: "majority" } });
  sdb.customers.updateOne({ "accounts.accountId": 1 },
                          { $inc: { "accounts.$.balance": NumberDecimal("-500.00") } });
  const inside  = balanceOf(sdb, 1);
  const outside = balanceOf(db, 1);
  session.abortTransaction();
  session.endSession();
  const afterAbort = balanceOf(db, 1);
  printjson({ insideTransaction: inside.balance,
              outsideTransaction: outside.balance,
              afterAbort: afterAbort.balance });
})();
// Expected: inside is 500 lower; outside and afterAbort are unchanged.
