# Portfolio 3: Transactions and Concurrency

**Case study:** NairaFlow Digital Bank<br>
**DBMS:** PostgreSQL 18 (pgAdmin 4 and psql)<br>
**Demo accounts:** 2001, 2002, 2003 (each funded with ₦10,000)

## Summary

The core banking operations are implemented as PostgreSQL functions, each running as a
single transaction. The demos show commit, automatic and explicit rollback, idempotent
retries and compensating reversals. Two concurrent sessions then reproduce a **lost update**,
fix it with **pessimistic locking** and with **SERIALIZABLE isolation**, and show that
`transfer_funds()` prevents double spending and deadlocks by design.

## Contents

| File | Purpose |
| --- | --- |
| [procedures.sql](procedures.sql) | `deposit_funds`, `transfer_funds`, `send_interbank_transfer`, `reverse_failed_transaction` |
| [demo-setup.sql](demo-setup.sql) | Creates the demo customer and accounts 2001–2003 |
| [transaction-demos.sql](transaction-demos.sql) | B1–B6: commit, rollback, idempotency, reversal, reconciliation |
| [concurrency-demos.sql](concurrency-demos.sql) | C1–C4 and D1–D2: two-session concurrency and deadlock demos |
| [screenshots/](screenshots/) | Evidence for every demo |

## Transaction demos (single session)

| Demo | What happens | Concept shown |
| --- | --- | --- |
| B1 | ₦2,500 transfer: debit, credit and two ledger lines saved together | Atomicity, commit |
| B2 | Transfer above the balance raises an error; nothing is saved | Automatic rollback |
| B3 | Same request retried with the same idempotency key; no second debit | Idempotency |
| B4 | Transfer visible inside the transaction, discarded by `ROLLBACK` | Isolation, explicit rollback |
| B5 | Interbank switch fails after debit; teller refused, operations reverses it; second reversal refused | Compensating transaction, segregation of duties |
| B6 | Reconciliation after all demos | Consistency (0 mismatches) |

## Concurrency demos (two sessions)

| Demo | Scenario | Outcome |
| --- | --- | --- |
| C1 | Two withdrawals read the same balance, then write back their own result | **Lost update**: ₦8,000 withdrawal silently overwritten; caught by reconciliation |
| C2 | Same, with `SELECT … FOR UPDATE` | Second session **waits**, then sees the real balance; over-withdrawal refused |
| C3 | Same, under `SERIALIZABLE` | Second session gets **"could not serialize access"** and must retry |
| C4 | Two `transfer_funds()` calls drain the same account | Second call waits, then fails with **insufficient funds**: no double spend |
| D1 | Two transfers lock accounts in opposite orders | **Deadlock detected**; PostgreSQL cancels one transaction |
| D2 | Same transfers through `transfer_funds()` | Accounts locked in ascending ID order: the second **queues**, both succeed |

## Key design decisions

- **Logic inside the database:** locking, validation and ledger writes happen in one function,
  so callers cannot forget a step.
- **Lock both accounts in ascending ID order:** prevents lost updates *and* deadlocks.
- **Idempotency key (`UNIQUE`):** a retried request returns the original transaction.
- **Reversals add, never edit:** a failed debit is refunded with a new CREDIT, recorded in `reversals`.
- **Role check on reversals:** only OPERATIONS or COMPLIANCE staff may approve refunds.

## How to reproduce

1. Build the database (Portfolio 1: `schema.sql` → `seed.sql` → `audit-triggers.sql`).
2. Run `procedures.sql`, then `demo-setup.sql` (once only).
3. Run the B demos in `transaction-demos.sql` one block at a time.
4. Open two psql sessions and follow `concurrency-demos.sql` line by line, in order.