# NoSQL Design and Suitability – NairaFlow Digital Bank

## 1. Overview

The same NairaFlow data used in Portfolios 1–3 was exported from PostgreSQL and modelled in
**MongoDB** (a document database), hosted on **MongoDB Atlas** (free tier, AWS eu-west-3 Paris,
a three-node replica set). Two collections were created:

| Collection | Documents | One document represents |
| --- | --- | --- |
| `customers` | 1,001 | A customer with their KYC records and accounts embedded |
| `transaction_events` | 51,658 | One transaction (1 Sept 2026 onwards) with its transfer details and ledger lines embedded |

Data was exported with PostgreSQL views ([export-views.sql](export-views.sql)) and imported
with MongoDB Compass. The export commands are listed in the Appendix.

## 2. Document model

### 2.1 Embedding vs referencing

| Data | Decision | Reason |
| --- | --- | --- |
| KYC documents inside `customers` | **Embed** | Always read with the customer; a customer has only one or two |
| Accounts inside `customers` | **Embed** | A profile screen needs all of a customer's accounts at once; few per customer |
| Ledger lines inside `transaction_events` | **Embed** | A transaction's debit and credit belong together and never change |
| Transfer details inside `transaction_events` | **Embed (optional field)** | Only transfers have them; deposits and withdrawals simply omit the field |
| Accounts referenced from `transaction_events` (`ledger.accountId`, `transfer.fromAccount`) | **Reference** | Transactions grow without limit; embedding them in customers would create unbounded documents |

In PostgreSQL, a customer profile is spread across **four tables** (`customers`,
`kyc_documents`, `accounts`, `account_types`). In MongoDB it is **one document**, read in a
single lookup.

### 2.2 Data types

The first export stored money as plain JSON numbers and dates as text. MongoDB would have
imported money as **floating point** (which can round) and dates as **strings**. The export was
changed to **MongoDB Extended JSON**, so money imports as **Decimal128** (exact) and dates as
**BSON Dates**. This applies the same principle as using `NUMERIC` instead of `FLOAT` in
PostgreSQL.

### 2.3 Schema validation

MongoDB accepts any document shape by default. A `$jsonSchema` validator on each collection
([01-collections.js](mongo/01-collections.js)) restores the rules that matter for a bank:
11-digit BVN, 10-digit NUBAN, money as Decimal128 and never negative, and fixed lists of
statuses and types. With `validationAction: "error"`, invalid documents are **rejected**.
A test customer with a 9-digit BVN and a negative balance was refused with
*"Document failed validation"*, naming both failed rules
([02-validation-test.js](mongo/02-validation-test.js)).

### 2.4 Indexes

| Index | Purpose |
| --- | --- |
| `customers.email`, `customers.bvn` (unique) | No duplicate customers |
| `customers.accounts.accountNumber` (unique, **multikey**) | Find a customer by any of their account numbers; no duplicate accounts |
| `transaction_events.{ledger.accountId, createdAt}` | Account statements, newest first |
| `transaction_events.{status, createdAt}` | Failed-transfer monitoring |
| `transaction_events.transfer.fromAccount` | Following money out of an account (graph traversal) |

Because `accounts` is an array, the `accounts.accountNumber` index is **multikey**: MongoDB
indexes every account number inside every customer document.

## 3. Results

### D1 – Customer profile in one read

Looking up the owner of account `9000000001` returned the full profile (KYC and all three
accounts) as one document. `explain()` showed an **EXPRESS_IXSCAN** on
`accounts.accountNumber_1`, examining **1 index key and 1 document** in **0 ms**.
EXPRESS_IXSCAN is MongoDB's fast path for an exact match on a **unique** index: since at most
one document can match, the general query planner is skipped.

### D2 – Account statement, with and without an index

| D2 statement (account 2001, October) | Keys examined | Docs examined | Returned | Time |
| --- | --- | --- | --- | --- |
| With index, first run | 8 | 8 | 8 | 29 ms |
| With index, repeat run | 8 | 8 | 8 | 1 ms |
| Without index (COLLSCAN + in-memory SORT) | 0 | 51,658 | 8 | 351 ms |

The index examined **6,457× fewer documents** and removed the in-memory sort, because entries
are already stored newest-first. The gap between the first and repeat runs (29 ms against 1 ms)
is caching, the same effect seen in Portfolio 2.

### D3 – Aggregation pipeline, cross-checked with PostgreSQL

A `$match → $group → $sort` pipeline computed daily totals by transaction type. The same totals
were computed in PostgreSQL with `GROUP BY`. **All six rows matched exactly:**

| Day | Type | Count | Total (₦) | PostgreSQL = MongoDB |
| --- | --- | --- | --- | --- |
| 2026-09-01 | DEPOSIT | 337 | 8,422,325.80 | ✅ |
| 2026-09-01 | TRANSFER | 1,043 | 5,241,167.74 | ✅ |
| 2026-09-01 | WITHDRAWAL | 357 | 3,726,561.12 | ✅ |
| 2026-09-02 | DEPOSIT | 395 | 9,725,049.74 | ✅ |
| 2026-09-02 | TRANSFER | 1,034 | 5,293,631.63 | ✅ |
| 2026-09-02 | WITHDRAWAL | 407 | 4,266,121.39 | ✅ |

This proves the migration lost no transactions and changed no amounts.

### D4 – Graph traversal: detecting a money-mule ring

A ring of three high-value transfers was planted in PostgreSQL using the Portfolio 3 functions:
**2001 → 2002 (₦55,000) → 2003 (₦54,000) → 2001 (₦53,000)**. In MongoDB, `$graphLookup`
followed money from account to account (each transfer's destination becomes the next search's
source, up to 4 hops) and flagged every chain that **returned to its starting account**.
The ring was detected from each of its members, with `returnsToStart: true`.

Only transfers of ₦50,000 or more were traversed. With 300,000 small random transfers across
2,000 accounts, almost every account is linked to every other within a few hops, so an
unfiltered traversal would flag "cycles" everywhere. Real anti-money-laundering rules likewise
focus on high-value patterns.

### D5 – Schema flexibility

A `trustedDevices` array was added to one customer with a single `updateOne`. No migration was
needed, the other 1,000 documents were unchanged, and the validator still accepted it (it only
enforces the fields it names). In PostgreSQL, this needs a new table or an `ALTER TABLE`.

## 4. Suitability: which model for which job

| Requirement | Relational (PostgreSQL) | Document (MongoDB) | Better fit |
| --- | --- | --- | --- |
| Moving money between accounts | ACID transactions, row locks, constraints across tables | Multi-document transactions exist but are more limited and costly | **Relational** |
| Ledger integrity and reconciliation | Foreign keys, CHECK constraints, append-only trigger | Validation per document; no foreign keys | **Relational** |
| Customer profile for the mobile app | 4-table join on every view | One document, one read | **Document** |
| Evolving optional data (devices, preferences, KYC variants) | Schema migrations | Add fields per document | **Document** |
| Event history and analytics | Strong with indexes | Strong with indexes and pipelines | Either |
| Following money flows (fraud) | Possible with recursive CTEs, awkward | `$graphLookup` built in | **Document** (a dedicated graph database for heavy use) |

**Recommendation: polyglot persistence.** PostgreSQL stays the **system of record** for
accounts, transfers and the ledger, because those need ACID guarantees and cross-table
integrity. MongoDB serves **read-heavy and flexible workloads**: customer profiles for the app,
the event history, and fraud analytics. Changes flow one way, from PostgreSQL to MongoDB.

## 5. Risks and trade-offs

- **Stale embedded data.** `customers.accounts.balance` is a snapshot taken at export. If money
  moves in PostgreSQL, MongoDB is out of date until it is refreshed. In production this needs
  change data capture (streaming changes from PostgreSQL), and the app must never treat the
  MongoDB balance as authoritative.
- **No cross-document integrity.** Nothing stops a `transaction_events` document referencing an
  account that does not exist. PostgreSQL's foreign keys prevent this.
- **Sensitive data.** BVNs are stored in plain text here (fictional data). In production they
  would need field-level encryption (for example MongoDB Queryable Encryption) and restricted access.
- **Least privilege.** The Atlas database user was created with the Atlas Admin role, which is
  more access than an application needs. Production should use a user limited to `readWrite`
  on the `nairaflow` database.
- **Network access.** Atlas only accepts connections from IP addresses on its access list.
  Connections were rejected at the network layer each time my IP changed, before the password
  was checked: defence in depth.

## 6. Limitations

- Only data from 1 September 2026 onwards was exported to `transaction_events`, to stay within
  the free tier and keep imports fast.
- Timestamps were exported as UTC without converting from local time; a production pipeline
  would store explicit time zones.
- The fraud ring was planted deliberately; the detection rule has not been tested against real
  transaction patterns.

## Appendix: export commands

Run in psql (pgAdmin → Tools → PSQL Tool) after `export-views.sql`. Each command must be on a
single line; adjust the path to your own repository folder.

```
\copy (SELECT doc FROM export_customers ORDER BY (doc->>'_id')::int) TO 'C:/Users/m.vima/Documents/GitHub/advanced-database-portfolio/portfolio-4-nosql/data/customers.json'
```

```
\copy (SELECT doc FROM export_transaction_events ORDER BY (doc->>'_id')::bigint) TO 'C:/Users/m.vima/Documents/GitHub/advanced-database-portfolio/portfolio-4-nosql/data/transaction_events.json'
```

Then import each file into its collection in Compass: **ADD DATA → Import JSON or CSV file**.