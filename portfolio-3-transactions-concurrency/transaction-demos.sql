-- =============================================================
-- NairaFlow – Portfolio 3 transaction demos (run one block at a time)
-- Demo accounts: 2001, 2002, 2003 (each starts with ₦10,000)
-- Run in pgAdmin unless marked "psql".
-- =============================================================


-- B1. Successful transfer (COMMIT): ₦2,500 from 2001 to 2002
SELECT transfer_funds(2001, 2002, 2500, 'DEMO-T1');

SELECT a.account_id, a.balance, le.entry_type, le.amount, le.balance_after
FROM accounts a
JOIN ledger_entries le ON le.account_id = a.account_id
JOIN transfers tr      ON tr.transaction_id = le.transaction_id
WHERE tr.idempotency_key = 'DEMO-T1'
ORDER BY le.entry_type DESC;
-- Expected: 2001 = 7500.00 (DEBIT), 2002 = 12500.00 (CREDIT)


-- B2. Failed transfer (automatic ROLLBACK): more than the balance
SELECT transfer_funds(2001, 2002, 50000, 'DEMO-T2');
-- Expected error: Insufficient funds: balance 7500.00, requested 50000

SELECT (SELECT balance FROM accounts WHERE account_id = 2001) AS balance_2001,
       (SELECT count(*) FROM transfers WHERE idempotency_key = 'DEMO-T2') AS demo_t2_rows;
-- Expected: 7500.00 and 0 (nothing was saved)


-- B3. Duplicate request (idempotency): retry DEMO-T1
SELECT transfer_funds(2001, 2002, 2500, 'DEMO-T1');
-- Expected: same transaction ID as B1, NOTICE "Duplicate request DEMO-T1",
-- and 2001 stays at 7500.00 (not 5000.00)


-- B4. Explicit ROLLBACK (psql). The prompt shows * while a transaction is open.
BEGIN;
SELECT transfer_funds(2001, 2003, 1000, 'DEMO-T3');
SELECT account_id, balance FROM accounts WHERE account_id IN (2001, 2003) ORDER BY account_id;
-- Inside the transaction: 2001 = 6500.00, 2003 = 11000.00
ROLLBACK;
SELECT account_id, balance FROM accounts WHERE account_id IN (2001, 2003) ORDER BY account_id;
-- After ROLLBACK: 2001 = 7500.00, 2003 = 10000.00 (nothing was saved)


-- B5. Interbank failure and reversal
-- Simulate a payment-switch timeout AFTER ₦4,000 is debited from 2003
SELECT send_interbank_transfer(2003, '000013', '0123456789', 'Beneficiary at Other Bank',
                               4000, 'DEMO-IB1', FALSE);
-- Returns a transaction ID. Replace TXID below with it.
-- 2003 is now 6000.00 and the transaction is FAILED.

-- B5a. Reversal by a TELLER (staff 4) must be refused
SELECT reverse_failed_transaction(TXID, 4, 'Switch timeout after debit');
-- Expected error: Staff 4 is not authorised to approve reversals

-- B5b. Reversal by OPERATIONS staff (staff 1) succeeds
SELECT reverse_failed_transaction(TXID, 1, 'Switch timeout after debit');

SELECT t.transaction_id, t.transaction_type, t.status, t.amount,
       r.reason, r.approved_by,
       (SELECT balance FROM accounts WHERE account_id = 2003) AS balance_2003
FROM transactions t
LEFT JOIN reversals r ON r.original_transaction_id = t.transaction_id
WHERE t.transaction_id = TXID;
-- Expected: status REVERSED, approved_by 1, balance_2003 = 10000.00

-- B5c. A second reversal must be refused
SELECT reverse_failed_transaction(TXID, 1, 'Second attempt');
-- Expected error: Only FAILED transactions can be reversed (status is REVERSED)


-- B6. Reconciliation: every stored balance must still match the ledger
SELECT a.account_id, a.balance AS stored_balance, s.ledger_balance
FROM accounts a
JOIN (
  SELECT account_id,
         SUM(CASE WHEN entry_type = 'CREDIT' THEN amount ELSE -amount END) AS ledger_balance
  FROM ledger_entries
  GROUP BY account_id
) s ON s.account_id = a.account_id
WHERE a.balance <> s.ledger_balance;
-- Expected: 0 rows