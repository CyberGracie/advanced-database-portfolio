-- =============================================================
-- NairaFlow Digital Bank – indexes for Portfolio 2
-- Each index targets specific queries in queries.sql.
-- =============================================================

-- I1. Composite + covering index for account statements (Q1)
--     and balance reconciliation (Q5).
--     Leading column account_id finds one account's rows; created_at keeps
--     them in date order, so the ORDER BY needs no separate sort step.
--     INCLUDE stores entry_type and amount in the index, allowing
--     index-only scans for the reconciliation sum.
CREATE INDEX idx_ledger_account_created
  ON ledger_entries (account_id, created_at)
  INCLUDE (entry_type, amount);

-- I2. Partial index on failed transactions only (Q2, Q6).
--     About 5% of transfers fail, so this index is far smaller than a full one
--     and only covers the rows operations and compliance staff look for.
CREATE INDEX idx_transactions_failed_created
  ON transactions (created_at)
  WHERE status = 'FAILED';

-- I3. Covering index for date-range reporting (Q3, Q4).
CREATE INDEX idx_transactions_created
  ON transactions (created_at)
  INCLUDE (status, transaction_type, amount);

-- I4. Foreign-key index on transfers.source_account_id (Q3, Q6 joins).
--     PostgreSQL does NOT index foreign keys automatically.
CREATE INDEX idx_transfers_source_account
  ON transfers (source_account_id);

-- Refresh planner statistics so it knows the indexes exist
ANALYZE;