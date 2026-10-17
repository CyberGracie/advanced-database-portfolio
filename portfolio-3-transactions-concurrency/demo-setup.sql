-- Demo customer with three accounts, each funded with ₦10,000 through deposit_funds()
INSERT INTO customers (first_name, last_name, email, phone, bvn, date_of_birth, kyc_status)
VALUES ('Demo', 'Customer', 'demo@nairaflow.test', '+2349000000001',
        '29999999901', '1990-05-01', 'VERIFIED');

INSERT INTO accounts (account_number, customer_id, account_type_id)
SELECT v.acct, c.customer_id, 1
FROM customers c,
     (VALUES ('9000000001'), ('9000000002'), ('9000000003')) AS v(acct)
WHERE c.email = 'demo@nairaflow.test';

SELECT deposit_funds(account_id, 10000)
FROM accounts
WHERE account_number IN ('9000000001', '9000000002', '9000000003');

-- Show the demo accounts and their IDs
SELECT account_id, account_number, balance
FROM accounts
WHERE account_number LIKE '9000%'
ORDER BY account_id;ss