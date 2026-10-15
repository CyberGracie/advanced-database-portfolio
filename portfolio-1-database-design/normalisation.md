# Normalisation and Design Decisions – NairaFlow Digital Bank

This document explains how the NairaFlow schema was derived from raw banking records,
how it reaches Third Normal Form (3NF) and Boyce–Codd Normal Form (BCNF), and where
it deliberately departs from full normalisation, and why.

## 1. Starting point: an unnormalised "transfer slip"

Before design, a transfer could be recorded as one flat record, like a paper slip:

| Field | Example |
| --- | --- |
| reference | NF20260315000214567 |
| date | 2026-03-15 10:42 |
| amount | 7,500.00 |
| status | SUCCESS |
| sender_name, sender_bvn, sender_phone | Adaeze Okafor, 22000000001, +2348030000001 |
| sender_account_number, sender_account_type, sender_daily_limit | 3000000001, SAVINGS, 1,000,000 |
| receiver_name, receiver_account_number | Tunde Adeyemi, 3000000002 |
| sender_kyc_documents | {NIN: DOC00000001, PASSPORT: …} |

**Problems with this form:**
- **Repeating group:** a customer can hold several KYC documents and several accounts, crammed into one field.
- **Update anomaly:** if Adaeze changes her phone number, every slip she ever sent must be edited.
- **Insert anomaly:** a new customer cannot be stored until they make a transfer.
- **Delete anomaly:** deleting a customer's only transfer deletes the customer's details too.
- **Inconsistency risk:** the SAVINGS daily limit is copied onto every slip and can drift out of step.

## 2. First Normal Form (1NF): atomic values, no repeating groups

Every field holds one value, and repeating groups move into their own tables:
- KYC documents become rows in `kyc_documents` (one row per document).
- Accounts become rows in `accounts` (one row per account).
- Each money movement is split into **ledger lines**: one DEBIT and one CREDIT row.

At this stage, a ledger line could be keyed by **(reference, account_number)**.

## 3. Second Normal Form (2NF): no partial dependencies

With the composite key (reference, account_number), some fields depend on only **part** of the key:
- `date`, `amount`, `status` depend on `reference` alone, because they describe the whole transaction.
- `entry_type` and `balance_after` depend on the full key, because they describe one account's side.

So the data is split:
- **`transactions`**: one row per movement (reference, type, amount, status, timestamps).
- **`ledger_entries`**: one row per account affected (transaction_id, account_id, entry_type, amount, balance_after).

Each table now has a single-column surrogate primary key (`transaction_id`, `entry_id`),
so no partial dependencies can exist.

## 4. Third Normal Form (3NF): no transitive dependencies

Some non-key fields still depend on other non-key fields:
- `account_number → customer → name, BVN, phone`. Customer details move to **`customers`**,
  and `accounts` keeps only `customer_id` (foreign key).
- `account_number → account_type → daily_transfer_limit`. Limits move to **`account_types`**,
  and `accounts` keeps only `account_type_id`.
- Transfer-specific details (source, destination, idempotency key, failure reason) only apply
  to transfers, so they move to **`transfers`**, linked one-to-one to `transactions`.
  This avoids empty columns on every deposit and withdrawal (a supertype/subtype design).
- Reversal details (reason, approver) move to **`reversals`**, which links the original and the
  compensating transaction.

## 5. Boyce–Codd Normal Form (BCNF)

BCNF requires every determinant to be a candidate key. In this schema, the only non-primary-key
determinants are natural identifiers that are declared `UNIQUE`, which makes them candidate keys:

| Table | Candidate keys |
| --- | --- |
| customers | customer_id, email, phone, bvn |
| accounts | account_id, account_number |
| transactions | transaction_id, reference |
| transfers | transfer_id, transaction_id, idempotency_key |
| kyc_documents | document_id, (document_type, document_number) |
| reversals | reversal_id, original_transaction_id, reversal_transaction_id |

No other column determines another, so the core schema is in BCNF.

## 6. Deliberate denormalisation

| Column | Why it is technically redundant | Why it is kept | How consistency is protected |
| --- | --- | --- | --- |
| `accounts.balance` | Equals the sum of the account's ledger entries | Showing a balance is the most frequent operation; summing ~385 entries per account on every request is wasteful | `CHECK (balance >= 0)` and a reconciliation query that lists any account where balance ≠ ledger sum (`04-balance-audit-clean.png` returns 0 rows) |
| `ledger_entries.balance_after` | Can be computed with a running total | Statements show the balance after each line without recalculating history | The ledger is append-only (trigger blocks UPDATE/DELETE), so stored values cannot be altered |
| `ledger_entries.amount` | Usually equals `transactions.amount` | Keeps each ledger line self-describing and allows future cases where they differ (e.g. fees split across lines) | Double-entry rule: debits and credits of a transaction must sum to zero |

## 7. Optional relationships

Two foreign keys are intentionally nullable (cardinality 0..1, shown as `>?` in the DBML):
- `kyc_documents.verified_by` is empty until a staff member verifies the document. A `CHECK`
  ensures `verified_by` and `verified_at` are set together.
- `transfers.destination_account_id` is empty for interbank transfers. The
  `chk_transfer_destination` constraint enforces that a transfer has **either** an internal
  destination **or** an external bank code and account number, never both and never neither.

## 8. Integrity rules enforced by the database

| Rule | Mechanism |
| --- | --- |
| Money is exact | `NUMERIC(15,2)`, never floating point |
| Amounts are positive | `CHECK (amount > 0)` |
| No negative balances | `CHECK (balance >= 0)` |
| Valid BVN and NUBAN formats | `CHECK` with regular expressions (11 and 10 digits) |
| Fixed status values | `CHECK (status IN (…))` |
| No duplicate transfers | `UNIQUE (idempotency_key)` |
| No self-transfers | `CHECK (source_account_id <> destination_account_id)` |
| A transaction is reversed at most once | `UNIQUE (original_transaction_id)` |
| Every change is traceable | Audit triggers write to `audit_log` (old and new values as JSONB) |
| Ledger history cannot be altered | `BEFORE UPDATE OR DELETE` trigger raises an error |

## 9. Implementation notes

- The DBML model uses `json` for audit snapshots; the PostgreSQL implementation uses `JSONB`,
  which is stored in binary form and can be indexed and queried efficiently.
- During seeding, a failed run left the identity sequences advanced (PostgreSQL does not roll
  back sequences), which caused a foreign key violation on the next run. The seed script now
  starts with `TRUNCATE … RESTART IDENTITY` so it can be re-run safely.