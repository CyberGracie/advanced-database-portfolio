-- =============================================================
-- NairaFlow – export relational data as MongoDB documents
-- MIT 8103 Portfolio 4: NoSQL and Advanced Data Models
-- Each view returns one JSON document per row (column "doc").
-- json_strip_nulls removes empty fields, so documents stay sparse.
-- =============================================================

-- 1. CUSTOMER PROFILES: customer + KYC documents + accounts, embedded in ONE document
CREATE OR REPLACE VIEW export_customers AS
SELECT json_strip_nulls(json_build_object(
  '_id',         c.customer_id,
  'name',        json_build_object('first', c.first_name, 'last', c.last_name),
  'email',       c.email,
  'phone',       c.phone,
  'bvn',         c.bvn,
  'dateOfBirth', c.date_of_birth,
  'kycStatus',   c.kyc_status,
  'createdAt',   c.created_at,
  'kyc', (SELECT json_agg(json_build_object(
                   'type',       k.document_type,
                   'number',     k.document_number,
                   'verifiedBy', k.verified_by,
                   'verifiedAt', k.verified_at))
          FROM kyc_documents k
          WHERE k.customer_id = c.customer_id),
  'accounts', (SELECT json_agg(json_build_object(
                        'accountId',     a.account_id,
                        'accountNumber', a.account_number,
                        'type',          at.type_name,
                        'balance',       a.balance,
                        'currency',      a.currency,
                        'status',        a.status) ORDER BY a.account_id)
               FROM accounts a
               JOIN account_types at ON at.account_type_id = a.account_type_id
               WHERE a.customer_id = c.customer_id)
)) AS doc
FROM customers c;

-- 2. TRANSACTION EVENTS: each transaction with its transfer details and
--    ledger lines embedded (September 2026 onwards, including all demos)
CREATE OR REPLACE VIEW export_transaction_events AS
SELECT json_strip_nulls(json_build_object(
  '_id',         t.transaction_id,
  'reference',   t.reference,
  'type',        t.transaction_type,
  'amount',      t.amount,
  'status',      t.status,
  'createdAt',   t.created_at,
  'completedAt', t.completed_at,
  'transfer', CASE WHEN tr.transfer_id IS NULL THEN NULL ELSE json_build_object(
                'fromAccount',        tr.source_account_id,
                'toAccount',          tr.destination_account_id,
                'beneficiaryBank',    tr.beneficiary_bank_code,
                'beneficiaryAccount', tr.beneficiary_account_number,
                'idempotencyKey',     tr.idempotency_key,
                'failureReason',      tr.failure_reason) END,
  'ledger', l.ledger
)) AS doc
FROM transactions t
LEFT JOIN transfers tr ON tr.transaction_id = t.transaction_id
LEFT JOIN (
  SELECT transaction_id,
         json_agg(json_build_object(
           'accountId',    account_id,
           'entry',        entry_type,
           'amount',       amount,
           'balanceAfter', balance_after) ORDER BY entry_id) AS ledger
  FROM ledger_entries
  WHERE created_at >= '2026-09-01'
  GROUP BY transaction_id
) l ON l.transaction_id = t.transaction_id
WHERE t.created_at >= '2026-09-01';