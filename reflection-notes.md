# Reflection Notes – MIT 8103 Advanced Database Portfolio

**Student:** Grace Emmanuel<br>
**Student ID:** 301912877<br>
**Programme:** Master of Information Technology, Miva Open University<br>
**Session:** 2026/2027 September Semester<br>
**Case study:** NairaFlow Digital Bank (fintech platform)

These are my working notes, written as I built the portfolio. They record what I did, what
went wrong, how I fixed it and what I learned. My final reflection in the LMS submission
will be condensed from them.

---

## Day 1 – Case study, repository and ER design (14–15 October 2026)

I chose NairaFlow Digital Bank, a simulated Nigerian fintech, as my case study, set up a
private GitHub repository, and designed a ten-table ER model in DBML using dbdiagram.io.

My first real problem was that my case study promised more than my database could do.
I had written about SMEs and interbank transfers, but the model only handled individual
customers and transfers between NairaFlow accounts. An assessor comparing the two would
have spotted the gap straight away. I added a scope statement and external-beneficiary
fields to `transfers`, so the design now matches what the case study claims.

dbdiagram then warned me that `verified_by` and `destination_account_id` were nullable
foreign keys. At first this looked like an error. It turned out to describe the business
correctly: a KYC document has no verifier until someone checks it, and an interbank
transfer has no internal destination account. I marked both as optional (`>?`).

The diagram layout took longer than I expected. My first attempts had lines looping
around the whole page. What finally worked was placing the tables that connect two others,
`ledger_entries` and `transfers`, *between* them, and lining up the rows each line
connects. Smaller issues taught me to check my evidence: Markdown merged my README lines
until I used `<br>`, Windows' hidden extensions gave me `er-diagram.png.png`, and one
export showed an old layout.

**Takeaway:** a design has to match its requirements, and a correct design can still be
hard to assess if the diagram and files around it are unclear.

---

## Day 2 – Schema, test data and audit triggers (15 October 2026)

I installed PostgreSQL 18 and pgAdmin, built the schema with primary keys, foreign keys
and `CHECK` constraints (including the either/or rule for transfer destinations), and
generated 1,000 customers, 2,000 accounts and 502,000 transactions with
`generate_series()`. The load took about four minutes. I added audit triggers, made
`ledger_entries` append-only, and wrote up the normalisation from unnormalised form to BCNF.

My first seed run failed, and every retry showed only *"current transaction is aborted"*
(SQLSTATE 25P02). It reminded me of chasing a security alert whose message hides the real
cause. pgAdmin had left the failed transaction open, so each new attempt was rejected
before it started. Running `ROLLBACK` exposed the original error: a foreign-key violation.

The cause surprised me. The failed run had used up staff IDs 1–20, and PostgreSQL does
not roll back sequences when a transaction fails, so the next run numbered staff from 21.
My script still linked documents to staff member 2, who no longer existed. I added
`TRUNCATE … RESTART IDENTITY` to the start of the seed script so it can be re-run safely.

I then tested the protections deliberately. A `GOLD` account type was rejected by the
`CHECK` constraint, an attempt to edit a ledger entry was blocked by the trigger, and the
reconciliation query found zero mismatches between stored balances and the ledger.

**Takeaway:** rules enforced inside the database cannot be skipped by a buggy application,
and a stored balance is only safe because something proves it matches the ledger. I also
learned that a rollback does not undo everything, sequences included.

---

## Day 3 – Query processing and optimisation (16 October 2026)

I wrote six business queries and measured each three times, using the median, before and
after adding four indexes. I also measured what the indexes cost in write speed and storage.

The account statement query (Q1) dropped from about 354 ms to 0.49 ms, roughly 725× faster,
reading 34 pages instead of about 15,000. Seeing that number made the idea of an index
concrete for me in a way the theory had not.

Then Q3 and Q5 came back *slower*, and my first assumption was that my indexes had made
them worse. Comparing the plans proved me wrong: they were identical before and after, with
the same cost estimates, so the indexes were never used. The difference was run-to-run
variation on my laptop. To test the planner's choice for Q5, I forced an index plan with
`SET enable_seqscan = off`. It read about 70% fewer pages but was no faster, because the
slow part is adding up 772,000 amounts, not reading them. The planner had been right.

The partial index on failed transactions was the most efficient result: 344 kB, around 75×
smaller than the covering index I3 on the same column, yet it made Q2 about 330× faster.

The day's biggest mistake came during the write-cost test. I meant to roll back 50,000
test rows, but the transaction was not active in pgAdmin, so they were committed. When I
tried to delete them, my own append-only trigger blocked me. It was a strange moment to be
locked out by a control I had built myself. I did a controlled override (disable the
trigger, delete only the identifiable test rows, re-enable it, all in one transaction) and
confirmed with the reconciliation query that the data was clean. From a security point of
view it showed both sides: the control stops ordinary changes, but a privileged user can
switch it off, which is why production systems separate application and admin roles and
audit privileged actions.

Smaller slips (forgetting to save the after plans, a file literally named `qN-plan.txt`,
running `EXPLAIN` with no query) taught me to check my evidence files before committing.

**Takeaway:** indexes transform selective queries, help moderately selective ones, and do
nothing for bulk aggregations, and they roughly doubled ledger insert time in my test.
Timings mean little without repeated runs, a control, and the execution plan beside them.

---

## Day 4 – Transactions and concurrency (17–18 October 2026)

I built the core banking operations as PostgreSQL functions (deposit, internal transfer,
interbank transfer and reversal), each running as one transaction, and tested them on three
demo accounts.

The single-session demos behaved as designed: a failed transfer saved nothing, a retried
request with the same idempotency key did not debit twice, and a teller was refused when
trying to approve a reversal. One detail tied back to Day 2: a transfer I rolled back in
psql had been given transaction ID 502005, and the next real transaction got 502006. The
rollback undid the transfer but not the ID, so real transaction IDs will always have gaps.

The concurrency demos were the most useful part of the course so far. In C1, I watched a
₦8,000 withdrawal disappear: both sessions read ₦12,500 and each wrote back its own result,
so the second overwrote the first. Nothing raised an error. The only thing that caught it
was the reconciliation query from Day 2, which flagged account 2002 (stored 7,500, ledger
12,500). That made the case for reconciliation better than any explanation.

`FOR UPDATE` fixed it by making the second session wait, and `SERIALIZABLE` fixed it by
rejecting the second update outright. Seeing one session simply hang until the other
committed made locking concrete. The deadlock demo showed PostgreSQL cancelling one
transaction after about a second, and the ordered-locking version showed the same two
transfers queueing and both succeeding.

Practical problems: I typed the database name at psql's Username prompt, so login failed.
I then switched to pgAdmin's PSQL Tool, which connected without a password.

**Takeaway:** concurrency bugs are silent, so they have to be designed out (locking, lock
ordering, isolation levels) and caught after the fact (reconciliation, audit trail). The
audit log showed every change I made to account 2002, which is exactly the trail an
investigator would need after a real incident.

---

## Day 5 – NoSQL and advanced data models (18–20 October 2026)

I modelled NairaFlow in MongoDB Atlas by exporting my PostgreSQL data as documents: each
customer with their accounts and KYC embedded, and each transaction with its ledger lines
embedded.

Getting connected took longer than the modelling. Compass first failed with *bad auth*, which I
fixed by resetting the password and entering it separately from the connection string. Then it
failed with a DNS error (`queryTxt ESERVFAIL`), and later with a TLS error because my IP address
had changed and Atlas's access list rejected me. That last one showed defence in depth in action:
the network layer refused me before my password was even checked.

My first export would have stored money as floating point and dates as text. Switching to
Extended JSON meant balances came in as exact Decimal128 values, the same lesson as NUMERIC
versus FLOAT on Day 2. The payoff came in D3: daily totals computed in MongoDB matched
PostgreSQL exactly, to the kobo, which proved the migration lost nothing.

The most satisfying result was D4. I planted a ₦55,000 → ₦54,000 → ₦53,000 ring between three
accounts, and `$graphLookup` found it by following money from account to account. I also learned
why I needed a ₦50,000 threshold: with 300,000 random small transfers, almost every account
connects to every other within a few hops.

Git caught me out too: my `.gitignore` did not stop a file that had already been committed, so I
had to untrack it with `git rm --cached`. Later I found the Portfolio 3 README had been pasted into
the Portfolio 4 folder by mistake, another reminder to check each file before committing.

**Takeaway:** the document model is excellent for reading a whole customer at once and for
flexible or connected data, but it gives up the cross-table integrity that makes PostgreSQL the
right place for the ledger. For a bank, the answer is both: PostgreSQL as the system of record,
MongoDB for profiles and analytics.

---

## Day 6 – Distributed and cloud databases (21 October 2026)

My MongoDB Atlas cluster turned out to be the best evidence I had. It is a three-server
replica set in AWS Paris: one primary that takes writes and two secondaries that copy it.

The most interesting finding happened without me doing anything. On 18 October, `db.hello()`
showed `shard-00-02` as the primary. On 21 October, the Atlas overview showed `shard-00-01` as
primary. Somewhere in between, the primary stepped down, the other servers held an election,
and a new primary took over, with no change to my data or connection string. I had expected
to only be able to describe failover on the free tier, but comparing two screenshots let me
show it had actually happened.

Read preferences made the replication visible: the same query was answered by `shard-00-01`
when reading from the primary and by `shard-00-00` when reading from a secondary.

The write-concern timings surprised me. I expected `w:"majority"` and `w:3` to be clearly
slower than `w:1`, but all three took about 115–120 ms, and `w:3` was even marginally faster.
Almost all of that time is the round trip between Lagos and Paris; copying between servers in
the same region costs only a few milliseconds. So for this setup, the safest option is
effectively free. Asking for `w:5` on three servers was refused outright, which I liked:
the database fails loudly rather than pretending a write is safe.

Two small slips: the shell had switched to the `test` database after reconnecting, so my
first read-preference tests ran against an empty collection, and I saved one screenshot in
the wrong portfolio folder. Both were quick to fix.

I originally planned to set up PostgreSQL replication with Docker, but decided the Atlas
replica set already provided stronger, real evidence. PostgreSQL replication and sharding are
covered as designs instead.

**Takeaway:** the failover I observed is exactly when `w:1` is dangerous. A write acknowledged
by the old primary but not yet copied would have been lost in the election. For money, NairaFlow
must use majority writes and majority reads, and accept the small latency cost as part of the
price of not losing customers' transactions.

---

## Day 7 – Final documentation and overall reflection

*Draft written after Day 3; to be revised once Days 4–6 are complete.*

Building NairaFlow showed me that database work is less about writing tables and queries
and more about translating business rules into structure, then proving the structure
behaves as intended.

The decision I am most confident about is enforcing key rules inside the database. In
testing, the `CHECK` constraint rejected an invalid account type, the append-only trigger
blocked an edit to the ledger, and reconciliation found zero mismatches between stored
balances and the ledger.

The optimisation work challenged my assumptions most. Q1 became about 725× faster, but Q5
showed that reading fewer pages does not always mean a faster query, and the indexes
roughly doubled write time. I now judge performance by plans and repeated measurements,
not by whether an index exists.

Several problems were of my own making: the failed seed transaction and the 50,000 test
rows I committed by mistake. Both taught me to check transaction state before acting and
to verify what has actually been committed. In production, I would add isolated test data,
explicit transaction checks and restricted database roles.

With more time, I would automate tests for the constraints, triggers, transfer rules and
reconciliation, script the collection of plans and timings, and test the design under
heavier concurrent load.

This work connects directly to my background in security operations. Diagnosing the
25P02 error and the unused indexes used the same habits I use in incident response:
following the evidence, testing a hypothesis, and separating the symptom from the cause.
That background also makes me notice auditability, least privilege and the risk of
excessive admin access, all of which came up in this portfolio.

Before submitting, I will check the ER diagram against the final schema, confirm the
scripts run from scratch, and make sure every claim in the documentation is backed by a
plan, timing or screenshot in the repository.