// =============================================================
// NairaFlow – MongoDB collections with JSON Schema validation
// MIT 8103 Portfolio 4: NoSQL and Advanced Data Models
// Run in mongosh (Compass > Open MongoDB shell)
// =============================================================
use("nairaflow");

// Customer profiles: one document per customer, accounts and KYC embedded
db.createCollection("customers", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "name", "email", "phone", "bvn", "kycStatus", "accounts"],
      properties: {
        email:     { bsonType: "string", pattern: "^.+@.+$" },
        bvn:       { bsonType: "string", pattern: "^[0-9]{11}$" },
        kycStatus: { enum: ["PENDING", "VERIFIED", "REJECTED"] },
        accounts: {
          bsonType: "array",
          minItems: 1,
          items: {
            bsonType: "object",
            required: ["accountId", "accountNumber", "type", "balance", "currency", "status"],
            properties: {
              accountNumber: { bsonType: "string", pattern: "^[0-9]{10}$" },
              type:          { enum: ["SAVINGS", "CURRENT", "WALLET"] },
              balance:       { bsonType: "decimal", minimum: 0 },
              currency:      { bsonType: "string" },
              status:        { enum: ["ACTIVE", "FROZEN", "CLOSED"] }
            }
          }
        }
      }
    }
  },
  validationLevel: "strict",
  validationAction: "error"
});

// Transaction events: one document per transaction, ledger lines embedded
db.createCollection("transaction_events", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "reference", "type", "amount", "status", "createdAt"],
      properties: {
        type:      { enum: ["DEPOSIT", "WITHDRAWAL", "TRANSFER", "REVERSAL"] },
        amount:    { bsonType: "decimal", minimum: 0, exclusiveMinimum: true },
        status:    { enum: ["PENDING", "SUCCESS", "FAILED", "REVERSED"] },
        createdAt: { bsonType: "date" },
        ledger: {
          bsonType: "array",
          items: {
            bsonType: "object",
            required: ["accountId", "entry", "amount"],
            properties: {
              entry:  { enum: ["DEBIT", "CREDIT"] },
              amount: { bsonType: "decimal" }
            }
          }
        }
      }
    }
  },
  validationLevel: "strict",
  validationAction: "error"
});

db.getCollectionNames();