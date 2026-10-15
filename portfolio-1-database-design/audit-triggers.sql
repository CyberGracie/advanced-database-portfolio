-- =============================================================
-- NairaFlow Digital Bank – audit trail and ledger protection
-- Run AFTER seed.sql.
-- To reload test data later, run schema.sql -> seed.sql -> this file
-- (schema.sql drops the tables, which removes these triggers too).
-- =============================================================

-- 1. Generic audit function: writes one audit_log row per change.
--    TG_ARGV[0] is the name of the table's primary key column.
CREATE OR REPLACE FUNCTION fn_audit_row_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  pk_column text := TG_ARGV[0];
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO audit_log (table_name, record_id, action, new_values)
    VALUES (TG_TABLE_NAME, (to_jsonb(NEW) ->> pk_column)::bigint, TG_OP, to_jsonb(NEW));
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO audit_log (table_name, record_id, action, old_values, new_values)
    VALUES (TG_TABLE_NAME, (to_jsonb(NEW) ->> pk_column)::bigint, TG_OP,
            to_jsonb(OLD), to_jsonb(NEW));
    RETURN NEW;

  ELSE  -- DELETE
    INSERT INTO audit_log (table_name, record_id, action, old_values)
    VALUES (TG_TABLE_NAME, (to_jsonb(OLD) ->> pk_column)::bigint, TG_OP, to_jsonb(OLD));
    RETURN OLD;
  END IF;
END;
$$;

-- 2. Attach the audit function to the tables that hold customer and money data
CREATE OR REPLACE TRIGGER trg_audit_customers
  AFTER INSERT OR UPDATE OR DELETE ON customers
  FOR EACH ROW EXECUTE FUNCTION fn_audit_row_change('customer_id');

CREATE OR REPLACE TRIGGER trg_audit_kyc_documents
  AFTER INSERT OR UPDATE OR DELETE ON kyc_documents
  FOR EACH ROW EXECUTE FUNCTION fn_audit_row_change('document_id');

CREATE OR REPLACE TRIGGER trg_audit_accounts
  AFTER INSERT OR UPDATE OR DELETE ON accounts
  FOR EACH ROW EXECUTE FUNCTION fn_audit_row_change('account_id');

CREATE OR REPLACE TRIGGER trg_audit_transactions
  AFTER INSERT OR UPDATE OR DELETE ON transactions
  FOR EACH ROW EXECUTE FUNCTION fn_audit_row_change('transaction_id');

CREATE OR REPLACE TRIGGER trg_audit_transfers
  AFTER INSERT OR UPDATE OR DELETE ON transfers
  FOR EACH ROW EXECUTE FUNCTION fn_audit_row_change('transfer_id');

CREATE OR REPLACE TRIGGER trg_audit_reversals
  AFTER INSERT OR UPDATE OR DELETE ON reversals
  FOR EACH ROW EXECUTE FUNCTION fn_audit_row_change('reversal_id');

CREATE OR REPLACE TRIGGER trg_audit_staff
  AFTER INSERT OR UPDATE OR DELETE ON staff
  FOR EACH ROW EXECUTE FUNCTION fn_audit_row_change('staff_id');

-- 3. Make the ledger append-only: new entries allowed, edits and deletes blocked
CREATE OR REPLACE FUNCTION fn_block_ledger_changes()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    'ledger_entries is append-only: % is not allowed. Correct errors with a reversal instead.',
    TG_OP;
END;
$$;

CREATE OR REPLACE TRIGGER trg_ledger_append_only
  BEFORE UPDATE OR DELETE ON ledger_entries
  FOR EACH ROW EXECUTE FUNCTION fn_block_ledger_changes();