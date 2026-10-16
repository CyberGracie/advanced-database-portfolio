-- =============================================================
-- Write-cost test: time 50,000 ledger inserts, then undo them.
-- Run once before creating indexes and once after.
--
-- In pgAdmin:
--   1. Click the arrow next to Execute and UNTICK "Auto commit?"
--   2. Highlight the EXPLAIN block below and press F5;
--      read "Execution Time" on the last line of the plan
--   3. Highlight ROLLBACK; on its own and press F5
--   4. Re-tick "Auto commit?"
-- Results are recorded in timings.md.
-- =============================================================

EXPLAIN (ANALYZE)
INSERT INTO ledger_entries (transaction_id, account_id, entry_type, amount, balance_after)
SELECT 1, 1 + (g % 2000), 'CREDIT', 1.00, 0
FROM generate_series(1, 50000) AS g;

ROLLBACK;