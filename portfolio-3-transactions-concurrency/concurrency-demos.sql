-- =============================================================
-- NairaFlow – Portfolio 3 concurrency demos
-- Two psql sessions (pgAdmin PSQL Tool tabs): Session A and Session B.
-- Run each line in the session shown, in this exact order.
-- Account 2002 starts at 12,500. A withdraws 8,000; B withdraws 5,000
-- (13,000 in total, more than the balance, so one must be refused).
-- Default isolation level: READ COMMITTED.
-- =============================================================


-- C1. THE PROBLEM: LOST UPDATE
-- The application reads the balance, calculates the new value itself,
-- then writes it back (read-modify-write) without locking.
-- A: BEGIN;
-- A: SELECT balance FROM accounts WHERE account_id = 2002;          -- 12500
-- B: BEGIN;
-- B: SELECT balance FROM accounts WHERE account_id = 2002;          -- 12500
-- A: UPDATE accounts SET balance = 4500 WHERE account_id = 2002;    -- 12500 - 8000
-- A: COMMIT;
-- B: UPDATE accounts SET balance = 7500 WHERE account_id = 2002;    -- 12500 - 5000
-- B: COMMIT;
-- Result: balance 7500. Both withdrawals "succeeded" but A's 8,000 was lost.
-- Detected by reconciliation: account 2002 stored 7500.00, ledger 12500.00.
-- Restore:
--    UPDATE accounts SET balance = 12500 WHERE account_id = 2002;


-- C2. FIX 1: PESSIMISTIC LOCKING WITH SELECT ... FOR UPDATE
-- A: BEGIN;
-- A: SELECT balance FROM accounts WHERE account_id = 2002 FOR UPDATE;   -- 12500
-- B: BEGIN;
-- B: SELECT balance FROM accounts WHERE account_id = 2002 FOR UPDATE;   -- BLOCKS (waits for A's lock)
-- A: UPDATE accounts SET balance = 4500 WHERE account_id = 2002;
-- A: COMMIT;
--    B unblocks and sees 4500.00 (the current balance, not a stale one)
-- B: ROLLBACK;                                                         -- 4500 < 5000: withdrawal refused
-- Result: no lost update; the over-withdrawal is refused.
-- Restore:
--    UPDATE accounts SET balance = 12500 WHERE account_id = 2002;


-- C3. FIX 2: SERIALIZABLE ISOLATION (conflict detection, no read locks)
-- A: BEGIN ISOLATION LEVEL SERIALIZABLE;
-- A: SELECT balance FROM accounts WHERE account_id = 2002;          -- 12500
-- B: BEGIN ISOLATION LEVEL SERIALIZABLE;
-- B: SELECT balance FROM accounts WHERE account_id = 2002;          -- 12500 (no blocking)
-- A: UPDATE accounts SET balance = 4500 WHERE account_id = 2002;
-- A: COMMIT;
-- B: UPDATE accounts SET balance = 7500 WHERE account_id = 2002;
--    ERROR: could not serialize access due to concurrent update
--    (prompt changes to nairaflow=!#)
-- B: ROLLBACK;                                                         -- the application would retry
-- Result: PostgreSQL rejects the update based on an out-of-date read.
-- Restore:
--    UPDATE accounts SET balance = 12500 WHERE account_id = 2002;


-- C4. transfer_funds() PREVENTS DOUBLE SPEND ON ITS OWN
-- The function locks both accounts with FOR UPDATE internally.
-- A: BEGIN;
-- A: SELECT transfer_funds(2002, 2001, 8000, 'DEMO-C4A');           -- succeeds, lock held
-- B: SELECT transfer_funds(2002, 2003, 8000, 'DEMO-C4B');           -- BLOCKS
-- A: COMMIT;
--    B unblocks: ERROR: Insufficient funds: balance 4500.00, requested 8000
--    (B's function rolled itself back automatically; no ROLLBACK needed)
-- Result: no double spend, without the caller having to remember to lock.


-- FINAL CHECK
-- Reconciliation query (Portfolio 2, Q5): 0 rows
-- Demo balances: 2001 = 15500.00, 2002 = 4500.00, 2003 = 10000.00
-- Total = 30,000 = the three original 10,000 deposits (no money created or lost)
-- audit_log shows every balance change to 2002 during C1–C4, including each restore.