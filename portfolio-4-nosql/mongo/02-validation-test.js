// NairaFlow – validation test: this insert MUST be rejected.
// It breaks two rules: a 9-digit BVN (must be 11 digits)
// and a negative account balance (minimum is 0).
use("nairaflow");

db.customers.insertOne({
  _id: 99999,
  name: { first: "Bad", last: "Data" },
  email: "bad@nairaflow.test",
  phone: "+2340000000000",
  bvn: "123456789",
  kycStatus: "VERIFIED",
  accounts: [{ accountId: 99999, accountNumber: "1234567890", type: "SAVINGS",
               balance: NumberDecimal("-500.00"), currency: "NGN", status: "ACTIVE" }]
});