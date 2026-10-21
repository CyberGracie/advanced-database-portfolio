# Advanced Database Systems Portfolio – MIT 8103

**Student:** Grace Emmanuel<br>
**Student ID:** 301912877<br>
**Programme:** Master of Information Technology, Miva Open University<br>
**Session:** 2026/2027 September Semester<br>
**Case study:** NairaFlow Digital Bank (fintech platform)

## Nature of the business

NairaFlow Digital Bank is a simulated Nigerian fintech that provides digital banking to
individual customers through mobile and web applications: savings, current and wallet
accounts, deposits, withdrawals, transfers between NairaFlow accounts, and outgoing interbank
transfers. It processes a high volume of small, frequent transactions, so its database must keep
balances exact even under concurrent use, prevent duplicate payments, support reversals of failed
transactions, and keep a complete audit trail.
Full statement: [case-study.md](portfolio-1-database-design/case-study.md).

## Users of the database

| User | What they do |
| --- | --- |
| Customers | Open accounts, deposit, withdraw, transfer funds, view statements |
| Operations staff | Verify customer identity (KYC), investigate and reverse failed transactions |
| Compliance officers / auditors | Review transaction logs, audit balances, flag suspicious activity |
| System services | Process transfers and write transaction and audit logs automatically |

## Major data stored

- Customers and KYC documents (including BVN)
- Account types and accounts (10-digit NUBAN, balance, status)
- Transactions: deposits, withdrawals, transfers and reversals
- A double-entry ledger (a debit and/or credit line for every money movement)
- Transfer details (source, destination or external beneficiary, idempotency key, failure reason)
- Reversals, staff records, and an audit log of every change to financial data

## Key database operations

1. **Transfer funds** atomically between accounts, with protection against duplicate requests.
2. **Reverse failed transactions** with compensating ledger entries, approved by authorised staff.
3. **Audit account balances** by reconciling each stored balance against its ledger.
4. Supporting operations: deposits, withdrawals, account statements and fraud-pattern checks.

## Portfolio summary

| # | Topic | Main write-up | Highlights |
| --- | --- | --- | --- |
| 1 | Database Design and Modelling | [normalisation.md](portfolio-1-database-design/normalisation.md) | 10-table ER model, double-entry ledger, constraints, audit triggers, append-only ledger, 502,000 seeded transactions |
| 2 | Query Processing and Optimisation | [analysis.md](portfolio-2-query-optimisation/analysis.md) | Account statement ~725× faster with a composite index; forced-index experiment showing why bulk queries do not benefit |
| 3 | Transactions and Concurrency | [README](portfolio-3-transactions-concurrency/README.md) | Atomic transfers, idempotency, reversals; lost update reproduced and fixed with `FOR UPDATE` and `SERIALIZABLE`; deadlock prevented by lock ordering |
| 4 | NoSQL and Advanced Data Models | [nosql-design.md](portfolio-4-nosql/nosql-design.md) | Document model in MongoDB Atlas; aggregation totals identical to PostgreSQL; `$graphLookup` detected a planted money-mule ring |
| 5 | Distributed and Cloud Databases | [distributed-design.md](portfolio-5-distributed-cloud/distributed-design.md) | Three-node replica set; real automatic failover observed; read preferences and write concerns tested; CAP, sharding and cloud security |

## Repository structure

```
advanced-database-portfolio/
├── portfolio-1-database-design/       Case study, ER diagram, schema, seed data, triggers, normalisation
├── portfolio-2-query-optimisation/    Queries, indexes, before/after plans, timings, analysis
├── portfolio-3-transactions-concurrency/  Banking functions, transaction and concurrency demos
├── portfolio-4-nosql/                 Export views, MongoDB scripts, sample data, design write-up
├── portfolio-5-distributed-cloud/     Replication tests, distributed design write-up
├── ai-use-log.md                      AI use declaration and log
├── reflection-notes.md                Individual technical reflection
└── README.md                          This page
```

Each portfolio folder has its own README and a `screenshots/` folder with the evidence.

## Tools

| Purpose | Tool |
| --- | --- |
| Relational database | PostgreSQL 18, pgAdmin 4, psql |
| Document database | MongoDB Atlas (free tier, MongoDB 8.0, AWS eu-west-3), MongoDB Compass, mongosh |
| ER modelling | dbdiagram.io (DBML) |
| Editing and version control | VS Code, Git, GitHub Desktop |

## How to run

Each portfolio folder has a README with step-by-step instructions. The work builds in order:

1. **Portfolio 1:** create a PostgreSQL database named `nairaflow`, then run `schema.sql` → `seed.sql` → `audit-triggers.sql`.
2. **Portfolio 2:** run the queries in `queries.sql` with `EXPLAIN (ANALYZE, BUFFERS)`, then `indexes.sql`, and compare.
3. **Portfolio 3:** run `procedures.sql` and `demo-setup.sql`, then follow `transaction-demos.sql` and `concurrency-demos.sql`.
4. **Portfolio 4:** run `export-views.sql`, export with `\copy`, then run the `mongo/` scripts in order against a MongoDB cluster.
5. **Portfolio 5:** run the blocks in `replication-tests.js` against the same cluster.

## Documentation

- [AI use log and declaration](ai-use-log.md)
- [Reflection notes](reflection-notes.md)
- Portfolio write-ups: linked in the Portfolio summary above

## References

- Abadi, D. (2012) 'Consistency tradeoffs in modern distributed database system design', *Computer*, 45(2), pp. 37–42.
- Elmasri, R. and Navathe, S.B. (2016) *Fundamentals of Database Systems*. 7th edn. Boston: Pearson.
- Gilbert, S. and Lynch, N. (2002) 'Brewer's conjecture and the feasibility of consistent, available, partition-tolerant web services', *ACM SIGACT News*, 33(2), pp. 51–59.
- Kleppmann, M. (2017) *Designing Data-Intensive Applications*. Sebastopol, CA: O'Reilly Media.
- MongoDB, Inc. (2026) *MongoDB Manual*. Available at: https://www.mongodb.com/docs/manual/ (Accessed: 21 October 2026).
- PostgreSQL Global Development Group (2026) *PostgreSQL 18 Documentation*. Available at: https://www.postgresql.org/docs/18/ (Accessed: 21 October 2026).
- Holistics (2026) *DBML – Database Markup Language*. Available at: https://dbml.dbdiagram.io/docs/ (Accessed: 21 October 2026).

AI assistance is declared separately in [ai-use-log.md](ai-use-log.md).