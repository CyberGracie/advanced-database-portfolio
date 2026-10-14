# Case Study: NairaFlow Digital Bank

## 1. Organisation Overview and Nature of the Business

NairaFlow Digital Bank is a simulated Nigerian fintech company that provides digital banking and payment services to individual customers across Nigeria. The platform meets the growing demand for convenient, secure and accessible financial services through mobile and web applications, so customers can manage their money without visiting a physical branch.

NairaFlow offers savings and current accounts, digital wallets, deposits, withdrawals, and transfers between NairaFlow accounts. Customers can fund their accounts through supported payment channels, send money to other users, monitor their transaction history, and download account statements in Nigerian Naira (NGN).

The customer base includes salaried employees, students, freelancers and traders. To support secure onboarding, NairaFlow keeps Know Your Customer (KYC) records for every customer, including Bank Verification Number (BVN) information, in line with Nigerian regulatory and data protection requirements.

As a digital-first provider, NairaFlow processes a high volume of small, frequent transactions. The database must keep balances consistent even when thousands of transfers run at the same time, prevent duplicate payments when a customer retries a request, and keep a complete audit trail of every financial movement. It must also support reconciliation, failed-payment handling and reversals. To achieve this, the system is built on strong transactional integrity (ACID), double-entry bookkeeping and controlled access to financial records.

**Scope of this portfolio:** the database models individual (retail) customers only. Interbank transfers are represented as outgoing transactions to an external beneficiary (bank code and account number); the interbank settlement process itself is out of scope.

## 2. Users of the Database

| User | What they do |
| --- | --- |
| Customers | Open accounts, deposit, withdraw, transfer funds, view statements |
| Operations staff | Verify customer identity (KYC), investigate and resolve failed transactions |
| Compliance officers / auditors | Review transaction logs, audit account balances, flag suspicious activity |
| System services | Process transfers automatically and write transaction and audit logs |

## 3. Major Data to Be Stored

- Customers and their KYC documents, including BVN
- Account types (savings, current, wallet) and their transfer limits
- Accounts (10-digit NUBAN account number, type, balance, status)
- Transactions: deposits, withdrawals, transfers and reversals
- Ledger entries: a debit and a credit record for every money movement (double-entry)
- Transfer details: source account, destination account, idempotency key, failure reason
- Reversals of failed transactions, including the reason and the approving staff member
- Staff records
- An audit log of every insert, update and delete on financial data

## 4. Key Operations

1. **Transfer funds:** move money between two accounts atomically, so the debit and credit either both succeed or both fail.
2. **Reverse failed transactions:** create compensating ledger entries for a transfer that failed part-way, and record who approved the reversal.
3. **Audit account balances:** confirm that each account's stored balance matches the sum of its ledger entries.
4. **Supporting operations:** deposits, withdrawals, account statements, and queries that flag suspicious activity such as repeated failed transfers.