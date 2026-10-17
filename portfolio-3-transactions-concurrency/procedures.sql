-- =============================================================
-- NairaFlow Digital Bank – banking procedures (PostgreSQL 18)
-- MIT 8103 Portfolio 3: Transactions and Concurrency
-- Each function runs as ONE transaction: if any step raises an
-- error, every change made by the function is rolled back.
-- =============================================================

-- Helper: generate a unique transaction reference, e.g. NF20261017A1B2C3D4E5
CREATE OR REPLACE FUNCTION fn_new_reference()
RETURNS varchar
LANGUAGE sql
AS $$
  SELECT 'NF' || to_char(clock_timestamp(), 'YYYYMMDD')
         || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 10));
$$;

-- -------------------------------------------------------------
-- 1. DEPOSIT: credit an active account and record it in the ledger
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION deposit_funds(p_account_id INT, p_amount NUMERIC)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  v_tx_id       BIGINT;
  v_new_balance NUMERIC(15,2);
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Deposit amount must be positive';
  END IF;

  UPDATE accounts
  SET balance = balance + p_amount
  WHERE account_id = p_account_id AND status = 'ACTIVE'
  RETURNING balance INTO v_new_balance;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account % does not exist or is not active', p_account_id;
  END IF;

  INSERT INTO transactions (reference, transaction_type, amount, status, completed_at)
  VALUES (fn_new_reference(), 'DEPOSIT', p_amount, 'SUCCESS', now())
  RETURNING transaction_id INTO v_tx_id;

  INSERT INTO ledger_entries (transaction_id, account_id, entry_type, amount, balance_after)
  VALUES (v_tx_id, p_account_id, 'CREDIT', p_amount, v_new_balance);

  RETURN v_tx_id;
END;
$$;

-- -------------------------------------------------------------
-- 2. INTERNAL TRANSFER: debit, credit and log atomically
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION transfer_funds(
  p_source_account_id INT,
  p_dest_account_id   INT,
  p_amount            NUMERIC,
  p_idempotency_key   VARCHAR)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  v_existing_tx   BIGINT;
  v_tx_id         BIGINT;
  v_source_bal    NUMERIC(15,2);
  v_dest_bal      NUMERIC(15,2);
  v_source_status VARCHAR(20);
  v_dest_status   VARCHAR(20);
BEGIN
  -- a) Idempotency: a repeated request returns the original transaction
  SELECT transaction_id INTO v_existing_tx
  FROM transfers
  WHERE idempotency_key = p_idempotency_key;

  IF FOUND THEN
    RAISE NOTICE 'Duplicate request %: returning existing transaction %',
                 p_idempotency_key, v_existing_tx;
    RETURN v_existing_tx;
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Transfer amount must be positive';
  END IF;
  IF p_source_account_id = p_dest_account_id THEN
    RAISE EXCEPTION 'Cannot transfer to the same account';
  END IF;

  -- b) Lock BOTH accounts, always in ascending account_id order.
  --    Locking prevents lost updates; a fixed order prevents deadlocks.
  PERFORM 1
  FROM accounts
  WHERE account_id IN (p_source_account_id, p_dest_account_id)
  ORDER BY account_id
  FOR UPDATE;

  -- c) Validate, now that nobody else can change these rows
  SELECT balance, status INTO v_source_bal, v_source_status
  FROM accounts WHERE account_id = p_source_account_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Source account % not found', p_source_account_id;
  END IF;

  SELECT status INTO v_dest_status
  FROM accounts WHERE account_id = p_dest_account_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Destination account % not found', p_dest_account_id;
  END IF;

  IF v_source_status <> 'ACTIVE' OR v_dest_status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Both accounts must be ACTIVE';
  END IF;

  IF v_source_bal < p_amount THEN
    RAISE EXCEPTION 'Insufficient funds: balance %, requested %', v_source_bal, p_amount;
  END IF;

  -- d) Record the transaction and transfer details
  INSERT INTO transactions (reference, transaction_type, amount, status, completed_at)
  VALUES (fn_new_reference(), 'TRANSFER', p_amount, 'SUCCESS', now())
  RETURNING transaction_id INTO v_tx_id;

  INSERT INTO transfers (transaction_id, source_account_id, destination_account_id, idempotency_key)
  VALUES (v_tx_id, p_source_account_id, p_dest_account_id, p_idempotency_key);

  -- e) Move the money and write both sides of the ledger
  UPDATE accounts SET balance = balance - p_amount
  WHERE account_id = p_source_account_id
  RETURNING balance INTO v_source_bal;

  UPDATE accounts SET balance = balance + p_amount
  WHERE account_id = p_dest_account_id
  RETURNING balance INTO v_dest_bal;

  INSERT INTO ledger_entries (transaction_id, account_id, entry_type, amount, balance_after)
  VALUES (v_tx_id, p_source_account_id, 'DEBIT',  p_amount, v_source_bal),
         (v_tx_id, p_dest_account_id,   'CREDIT', p_amount, v_dest_bal);

  RETURN v_tx_id;
END;
$$;

-- -------------------------------------------------------------
-- 3. INTERBANK TRANSFER: the customer is debited first, then the
--    external payment switch responds. p_switch_succeeds = FALSE
--    simulates a switch timeout AFTER the debit, which leaves a
--    FAILED transaction where money has left the account. This is
--    the real-world case that needs a reversal.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION send_interbank_transfer(
  p_source_account_id   INT,
  p_bank_code           CHAR(6),
  p_beneficiary_account CHAR(10),
  p_beneficiary_name    VARCHAR,
  p_amount              NUMERIC,
  p_idempotency_key     VARCHAR,
  p_switch_succeeds     BOOLEAN DEFAULT TRUE)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  v_tx_id BIGINT;
  v_bal   NUMERIC(15,2);
BEGIN
  SELECT transaction_id INTO v_tx_id
  FROM transfers WHERE idempotency_key = p_idempotency_key;
  IF FOUND THEN
    RETURN v_tx_id;
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Transfer amount must be positive';
  END IF;

  SELECT balance INTO v_bal
  FROM accounts
  WHERE account_id = p_source_account_id AND status = 'ACTIVE'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Source account % not found or not active', p_source_account_id;
  END IF;
  IF v_bal < p_amount THEN
    RAISE EXCEPTION 'Insufficient funds: balance %, requested %', v_bal, p_amount;
  END IF;

  -- Debit the customer (money leaves NairaFlow)
  UPDATE accounts SET balance = balance - p_amount
  WHERE account_id = p_source_account_id
  RETURNING balance INTO v_bal;

  INSERT INTO transactions (reference, transaction_type, amount, status, completed_at)
  VALUES (fn_new_reference(), 'TRANSFER', p_amount,
          CASE WHEN p_switch_succeeds THEN 'SUCCESS' ELSE 'FAILED' END,
          CASE WHEN p_switch_succeeds THEN now() END)
  RETURNING transaction_id INTO v_tx_id;

  INSERT INTO transfers (transaction_id, source_account_id, beneficiary_bank_code,
                         beneficiary_account_number, beneficiary_name,
                         idempotency_key, failure_reason)
  VALUES (v_tx_id, p_source_account_id, p_bank_code, p_beneficiary_account,
          p_beneficiary_name, p_idempotency_key,
          CASE WHEN p_switch_succeeds THEN NULL
               ELSE 'Timeout from payment switch after debit' END);

  INSERT INTO ledger_entries (transaction_id, account_id, entry_type, amount, balance_after)
  VALUES (v_tx_id, p_source_account_id, 'DEBIT', p_amount, v_bal);

  RETURN v_tx_id;
END;
$$;

-- -------------------------------------------------------------
-- 4. REVERSE A FAILED TRANSACTION: refund the debited account with
--    a compensating CREDIT. The ledger is never edited.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION reverse_failed_transaction(
  p_transaction_id BIGINT,
  p_staff_id       INT,
  p_reason         VARCHAR)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  v_status          VARCHAR(20);
  v_amount          NUMERIC(15,2);
  v_staff_role      VARCHAR(30);
  v_debited_account INT;
  v_reversal_tx     BIGINT;
  v_bal             NUMERIC(15,2);
BEGIN
  -- a) Only operations or compliance staff may approve reversals
  SELECT role INTO v_staff_role FROM staff WHERE staff_id = p_staff_id;
  IF NOT FOUND OR v_staff_role NOT IN ('OPERATIONS', 'COMPLIANCE') THEN
    RAISE EXCEPTION 'Staff % is not authorised to approve reversals', p_staff_id;
  END IF;

  -- b) Lock the original transaction so two staff cannot reverse it at once
  SELECT status, amount INTO v_status, v_amount
  FROM transactions
  WHERE transaction_id = p_transaction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transaction % not found', p_transaction_id;
  END IF;
  IF v_status <> 'FAILED' THEN
    RAISE EXCEPTION 'Only FAILED transactions can be reversed (status is %)', v_status;
  END IF;

  -- c) Find the account that was actually debited
  SELECT account_id INTO v_debited_account
  FROM ledger_entries
  WHERE transaction_id = p_transaction_id AND entry_type = 'DEBIT';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transaction % has no debit to reverse (no money moved)', p_transaction_id;
  END IF;

  -- d) Refund the customer
  UPDATE accounts SET balance = balance + v_amount
  WHERE account_id = v_debited_account
  RETURNING balance INTO v_bal;

  INSERT INTO transactions (reference, transaction_type, amount, status, completed_at)
  VALUES (fn_new_reference(), 'REVERSAL', v_amount, 'SUCCESS', now())
  RETURNING transaction_id INTO v_reversal_tx;

  INSERT INTO ledger_entries (transaction_id, account_id, entry_type, amount, balance_after)
  VALUES (v_reversal_tx, v_debited_account, 'CREDIT', v_amount, v_bal);

  INSERT INTO reversals (original_transaction_id, reversal_transaction_id, reason, approved_by)
  VALUES (p_transaction_id, v_reversal_tx, p_reason, p_staff_id);

  -- e) Mark the original as reversed
  UPDATE transactions SET status = 'REVERSED'
  WHERE transaction_id = p_transaction_id;

  RETURN v_reversal_tx;
END;
$$;