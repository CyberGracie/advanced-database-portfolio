-- =============================================================
-- NairaFlow Digital Bank – synthetic test data (PostgreSQL)
-- Run AFTER schema.sql, on empty tables, BEFORE audit-triggers.sql.
-- To re-run: run schema.sql first (it rebuilds empty tables).
-- All data is fictional and generated with generate_series().
-- =============================================================

BEGIN;

-- 0. Start from empty tables with every ID counter reset to 1.
--    (Sequences are not rolled back by a failed transaction, so a
--    previous failed run would otherwise leave gaps in the IDs.)
TRUNCATE audit_log, reversals, transfers, ledger_entries, transactions,
         accounts, kyc_documents, staff, customers, account_types
RESTART IDENTITY CASCADE;

DROP TABLE IF EXISTS seed_moves;

-- 1. Account types
INSERT INTO account_types (type_name, daily_transfer_limit) VALUES
  ('SAVINGS', 1000000.00),
  ('CURRENT', 5000000.00),
  ('WALLET',   200000.00);

-- 2. Staff (20)
INSERT INTO staff (full_name, email, role)
SELECT 'Staff Member ' || g,
       'staff' || g || '@nairaflow.test',
       (ARRAY['TELLER','OPERATIONS','COMPLIANCE','AUDITOR'])[1 + (g % 4)]
FROM generate_series(1, 20) AS g;

-- 3. Customers (1,000)
INSERT INTO customers (first_name, last_name, email, phone, bvn,
                       date_of_birth, kyc_status, created_at)
SELECT
  (ARRAY['Adaeze','Tunde','Chiamaka','Ibrahim','Funmilayo',
         'Emeka','Zainab','Segun','Ngozi','Musa'])[1 + (g % 10)],
  (ARRAY['Okafor','Adeyemi','Bello','Eze','Okonkwo',
         'Abubakar','Balogun','Nwosu','Lawal','Danjuma'])[1 + ((g / 10) % 10)],
  'customer' || g || '@nairaflow.test',
  '+234803' || lpad(g::text, 7, '0'),
  (22000000000 + g)::text,                         -- 11-digit fictional BVN
  DATE '1965-01-01' + (random() * 13000)::int,
  CASE WHEN g % 20 = 0 THEN 'PENDING' ELSE 'VERIFIED' END,
  TIMESTAMP '2025-06-01' + random() * INTERVAL '180 days'
FROM generate_series(1, 1000) AS g;

-- 4. KYC documents (one per customer; only verified ones have a verifier)
INSERT INTO kyc_documents (customer_id, document_type, document_number,
                           verified_by, verified_at)
SELECT c.customer_id,
       (ARRAY['NIN','PASSPORT','DRIVERS_LICENCE'])[1 + (c.customer_id % 3)],
       'DOC' || lpad(c.customer_id::text, 8, '0'),
       CASE WHEN c.kyc_status = 'VERIFIED' THEN 1 + (c.customer_id % 20) END,
       CASE WHEN c.kyc_status = 'VERIFIED' THEN c.created_at + INTERVAL '1 day' END
FROM customers c;

-- 5. Accounts (2,000 = two per customer)
INSERT INTO accounts (account_number, customer_id, account_type_id, opened_at)
SELECT (3000000000 + g)::text,                     -- 10-digit fictional NUBAN
       1 + ((g - 1) % 1000),
       1 + (g % 3),
       TIMESTAMP '2025-12-01' + random() * INTERVAL '30 days'
FROM generate_series(1, 2000) AS g;

-- 6. Plan every money movement in a temporary working table
CREATE TEMP TABLE seed_moves AS
-- 2,000 opening deposits, one per account
SELECT g::bigint                  AS transaction_id,
       'DEPOSIT'::varchar(20)     AS transaction_type,
       g                          AS account_id,
       NULL::int                  AS dest_account_id,
       round((200000 + random() * 1800000)::numeric, 2) AS amount,
       'SUCCESS'::varchar(20)     AS status,
       TIMESTAMP '2026-01-01' + g * INTERVAL '1 second' AS created_at
FROM generate_series(1, 2000) AS g
UNION ALL
-- 100,000 deposits
SELECT g, 'DEPOSIT', 1 + floor(random() * 2000)::int, NULL,
       round((1000 + random() * 49000)::numeric, 2), 'SUCCESS',
       TIMESTAMP '2026-01-02' + random() * INTERVAL '270 days'
FROM generate_series(2001, 102000) AS g
UNION ALL
-- 100,000 withdrawals
SELECT g, 'WITHDRAWAL', 1 + floor(random() * 2000)::int, NULL,
       round((1000 + random() * 19000)::numeric, 2), 'SUCCESS',
       TIMESTAMP '2026-01-02' + random() * INTERVAL '270 days'
FROM generate_series(102001, 202000) AS g
UNION ALL
-- 300,000 internal transfers; about 5% fail. Destination is never the source.
SELECT g, 'TRANSFER', src,
       1 + ((src + floor(random() * 1999)::int) % 2000),
       round((100 + random() * 9900)::numeric, 2),
       CASE WHEN random() < 0.05 THEN 'FAILED' ELSE 'SUCCESS' END,
       TIMESTAMP '2026-01-02' + random() * INTERVAL '270 days'
FROM (SELECT g, 1 + floor(random() * 2000)::int AS src
      FROM generate_series(202001, 502000) AS g) AS t;

-- 7. Transactions
INSERT INTO transactions (transaction_id, reference, transaction_type,
                          amount, status, created_at, completed_at)
SELECT transaction_id,
       'NF' || to_char(created_at, 'YYYYMMDD') || lpad(transaction_id::text, 9, '0'),
       transaction_type, amount, status, created_at,
       CASE WHEN status = 'SUCCESS' THEN created_at + INTERVAL '2 seconds' END
FROM seed_moves;

-- 8. Transfer details (failed ones get a failure reason)
INSERT INTO transfers (transaction_id, source_account_id, destination_account_id,
                       idempotency_key, failure_reason)
SELECT transaction_id, account_id, dest_account_id,
       md5(transaction_id::text || '-nairaflow'),
       CASE WHEN status = 'FAILED' THEN
         (ARRAY['Insufficient funds',
                'Destination account unavailable',
                'Timeout from payment switch'])[1 + (transaction_id % 3)::int]
       END
FROM seed_moves
WHERE transaction_type = 'TRANSFER';

-- 9. Double-entry ledger (successful movements only)
INSERT INTO ledger_entries (transaction_id, account_id, entry_type, amount,
                            balance_after, created_at)
SELECT transaction_id, account_id, 'CREDIT', amount, 0, created_at
FROM seed_moves WHERE transaction_type = 'DEPOSIT'
UNION ALL
SELECT transaction_id, account_id, 'DEBIT', amount, 0, created_at
FROM seed_moves WHERE transaction_type = 'WITHDRAWAL'
UNION ALL
SELECT transaction_id, account_id, 'DEBIT', amount, 0, created_at
FROM seed_moves WHERE transaction_type = 'TRANSFER' AND status = 'SUCCESS'
UNION ALL
SELECT transaction_id, dest_account_id, 'CREDIT', amount, 0, created_at
FROM seed_moves WHERE transaction_type = 'TRANSFER' AND status = 'SUCCESS';

-- 10. Running balance after each entry, per account, in time order
UPDATE ledger_entries le
SET balance_after = r.running_balance
FROM (
  SELECT entry_id,
         SUM(CASE WHEN entry_type = 'CREDIT' THEN amount ELSE -amount END)
           OVER (PARTITION BY account_id ORDER BY created_at, entry_id) AS running_balance
  FROM ledger_entries
) AS r
WHERE le.entry_id = r.entry_id;

-- 11. Cached account balance = sum of that account's ledger
UPDATE accounts a
SET balance = s.total
FROM (
  SELECT account_id,
         SUM(CASE WHEN entry_type = 'CREDIT' THEN amount ELSE -amount END) AS total
  FROM ledger_entries
  GROUP BY account_id
) AS s
WHERE a.account_id = s.account_id;

-- 12. Move the transaction ID counter past the seeded IDs
SELECT setval(pg_get_serial_sequence('transactions', 'transaction_id'),
              (SELECT max(transaction_id) FROM transactions));

COMMIT;

-- Refresh the statistics the query planner uses (important for Portfolio 2)
ANALYZE;