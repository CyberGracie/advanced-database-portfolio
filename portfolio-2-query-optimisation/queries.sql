-- =============================================================
-- NairaFlow Digital Bank – business queries (PostgreSQL 18)
-- MIT 8103 Portfolio 2: Query Processing and Optimisation
-- Each query supports a real NairaFlow operation.
-- =============================================================

-- Q1. Account statement: one customer's account activity for March 2026
--     (Customers viewing their statement in the app – the most frequent query)
SELECT le.created_at,
       t.reference,
       t.transaction_type,
       le.entry_type,
       le.amount,
       le.balance_after
FROM ledger_entries le
JOIN transactions t ON t.transaction_id = le.transaction_id
WHERE le.account_id = 1042
  AND le.created_at >= '2026-03-01'
  AND le.created_at <  '2026-04-01'
ORDER BY le.created_at;

-- Q2. Failed transfers on one day
--     (Operations staff investigating failures, before deciding on reversals)
SELECT t.reference,
       t.amount,
       t.created_at,
       tr.source_account_id,
       tr.destination_account_id,
       tr.failure_reason
FROM transactions t
JOIN transfers tr ON tr.transaction_id = t.transaction_id
WHERE t.status = 'FAILED'
  AND t.created_at >= '2026-09-15'
  AND t.created_at <  '2026-09-16'
ORDER BY t.created_at DESC;

-- Q3. Top 10 customers by value of successful transfers sent in Q3 2026
--     (Management reporting)
SELECT c.customer_id,
       c.first_name || ' ' || c.last_name AS customer_name,
       count(*)      AS transfers_sent,
       sum(t.amount) AS total_sent
FROM transfers tr
JOIN transactions t ON t.transaction_id = tr.transaction_id
JOIN accounts a     ON a.account_id     = tr.source_account_id
JOIN customers c    ON c.customer_id    = a.customer_id
WHERE t.status = 'SUCCESS'
  AND t.created_at >= '2026-07-01'
  AND t.created_at <  '2026-10-01'
GROUP BY c.customer_id, customer_name
ORDER BY total_sent DESC
LIMIT 10;

-- Q4. Daily totals by transaction type for September 2026
--     (Finance dashboard)
SELECT created_at::date  AS day,
       transaction_type,
       count(*)           AS transaction_count,
       sum(amount)        AS total_amount
FROM transactions
WHERE status = 'SUCCESS'
  AND created_at >= '2026-09-01'
  AND created_at <  '2026-10-01'
GROUP BY day, transaction_type
ORDER BY day, transaction_type;

-- Q5. Balance reconciliation: accounts whose stored balance differs from the ledger
--     (Audit account balances – a key operation in the case study)
SELECT a.account_id,
       a.balance AS stored_balance,
       s.ledger_balance
FROM accounts a
JOIN (
  SELECT account_id,
         SUM(CASE WHEN entry_type = 'CREDIT' THEN amount ELSE -amount END) AS ledger_balance
  FROM ledger_entries
  GROUP BY account_id
) s ON s.account_id = a.account_id
WHERE a.balance <> s.ledger_balance;

-- Q6. Suspicious activity: accounts with 3+ failed transfers in September 2026
--     (Compliance / fraud monitoring)
SELECT tr.source_account_id,
       a.account_number,
       count(*)          AS failed_attempts,
       min(t.created_at) AS first_failure,
       max(t.created_at) AS last_failure
FROM transfers tr
JOIN transactions t ON t.transaction_id = tr.transaction_id
JOIN accounts a     ON a.account_id     = tr.source_account_id
WHERE t.status = 'FAILED'
  AND t.created_at >= '2026-09-01'
  AND t.created_at <  '2026-10-01'
GROUP BY tr.source_account_id, a.account_number
HAVING count(*) >= 3
ORDER BY failed_attempts DESC;