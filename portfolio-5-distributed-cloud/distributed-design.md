# Distributed and Cloud Database Design – NairaFlow Digital Bank

## 1. Environment

| Component | Deployment |
| --- | --- |
| MongoDB (Portfolio 4) | **MongoDB Atlas**, free tier, version 8.0.34, **three-node replica set** on AWS **eu-west-3 (Paris)** |
| PostgreSQL (Portfolios 1–3) | Single local instance (PostgreSQL 18) – the system of record in this portfolio |
| Client | MongoDB Compass / mongosh, connecting from Lagos over TLS |

All tests are in [replication-tests.js](replication-tests.js); evidence is in [screenshots/](screenshots/).

## 2. Replication: one primary, two secondaries

`db.hello()` showed three servers (`hosts`) forming the replica set `atlas-6ht26w-shard-0`.
One server is the **primary**, which accepts all writes; the other two are **secondaries**,
which continuously copy the primary's operations (its *oplog*) and can serve reads.

### 2.1 Failover observed

The primary changed between two observations, with no action from me:

| Server | 18 October (`db.hello()`) | 21 October (Atlas overview and `db.hello()`) |
| --- | --- | --- |
| `…shard-00-00` | Secondary | Secondary |
| `…shard-00-01` | Secondary | **Primary** |
| `…shard-00-02` | **Primary** | Secondary |

Between these dates, the primary stepped down (most likely during routine Atlas maintenance),
the remaining members **held an election**, and `shard-00-01` became primary. The data, the
connection string and my queries were unaffected. This is **automatic failover**, the main
availability benefit of a replica set.

## 3. Read preferences

The same query (`customers`, `_id: 1001`) was served by different servers depending on the
read preference:

| Read preference | Server that answered |
| --- | --- |
| `primary` (default) | `ac-mw2qdgc-shard-00-01` (the primary) |
| `secondary` | `ac-mw2qdgc-shard-00-00` (a secondary) |

Reading from secondaries spreads load, but a secondary may be slightly behind the primary.

## 4. Write concerns

A write concern sets how many servers must confirm a write before it is acknowledged.
Fifteen inserts were timed at each level (from Lagos to Paris):

| Write concern | Median | Min | Max |
| --- | --- | --- | --- |
| `w:1` (primary only) | 117 ms | 115 ms | 132 ms |
| `w:"majority"` (2 of 3) | 121 ms | 115 ms | 129 ms |
| `w:3` (all three) | 116 ms | 112 ms | 126 ms |

The three levels were **statistically indistinguishable**: `w:3` was even marginally faster
than `w:1`. Almost all of the ~115 ms is the **Lagos–Paris network round trip**; copying a
write between servers in the **same AWS region** takes only a few milliseconds. So in this
deployment, the extra durability of `w:"majority"` is effectively **free**. It would cost more
if secondaries were placed in other regions for disaster recovery, because every write would
then wait for a cross-region copy.

Requesting `w:5` on a three-node set was **rejected** with
`MongoWriteConcernError[UnsatisfiableWriteConcern]: Not enough data-bearing nodes`.
MongoDB refuses rather than acknowledging a write it cannot make as durable as requested.

A `readConcern("majority")` read returned only data confirmed by at least two of three
servers, which cannot be rolled back by a failover.

## 5. Why this matters for money

With `w:1`, the primary acknowledges a write **before** any secondary has it. If the primary
fails at that moment, the new primary (elected as in section 2.1) never received the write,
and it is **rolled back**: a "successful" transfer disappears. With `w:"majority"`, a write is
acknowledged only once a majority holds it, and an election always chooses a member that has
it. **NairaFlow should use `w:"majority"` and `readConcern("majority")` for all money
movement.** Applications should also enable *retryable writes*, so a transfer interrupted by
an election is retried once on the new primary; the idempotency key from Portfolio 3 ensures
a retry can never debit twice.

## 6. Consistency and the CAP theorem

The CAP theorem states that during a **network partition**, a distributed database must
choose between **consistency** (every read sees the latest write) and **availability** (every
request gets an answer). The PACELC extension adds that, even without a partition, there is a
trade-off between **latency** and **consistency**.

MongoDB lets each operation choose its position:

| NairaFlow workload | Settings | Trade-off chosen |
| --- | --- | --- |
| Transfers, balances, ledger | Primary reads, `w:"majority"`, `readConcern("majority")` | **Consistency** over availability: better to refuse a transfer than show a wrong balance |
| Customer profile in the app | Primary or `primaryPreferred` | Mostly consistent; can fall back if the primary is briefly unavailable |
| Reports, dashboards, fraud analytics (Portfolio 4) | `secondary` reads | **Availability and lower load** over freshness: a few milliseconds of lag is acceptable |

PostgreSQL makes the same choice through **synchronous replication**
(`synchronous_commit = on` with `synchronous_standby_names`): a commit waits until a standby
confirms it, the equivalent of `w:"majority"`.

## 7. Multi-document ACID transactions

MongoDB supports multi-document transactions on a replica set, which NairaFlow needs for a
transfer: debit one document, credit another, record an event, all or nothing. I ran a transfer
between two customer documents inside a session with `readConcern: "snapshot"` and
`writeConcern: "majority"` (`transaction-test.js`).

| Test | What happened |
| --- | --- |
| Successful transfer (T1) | 1,000 moved from account 1 to account 2; both balances changed and one event was written, under one commit (`t1-transaction-commit.png`) |
| Transfer over the balance (T2) | The debit was refused, the transaction aborted, and **neither** balance changed; no event was written (`t2-transaction-abort.png`) |
| Isolation (T3) | A debit inside an open transaction read 500 lower inside the session but unchanged outside it; after the abort it was unchanged everywhere (`t3-transaction-isolation.png`) |

So the three writes commit together or not at all, and an uncommitted change stays invisible to
other readers until it commits. This is the guarantee PostgreSQL gives `transfer_funds()` in
Portfolio 3, now across a three-node cluster rather than one machine. It costs more than a
single-document update, so MongoDB would own transfers only if the ledger did not already live
in PostgreSQL; here PostgreSQL stays the system of record.

## 8. Sharding NairaFlow at scale

Replication copies **all** data to every node; **sharding** splits data across nodes so that
storage and write throughput scale horizontally. NairaFlow does not need sharding at
1,000 customers, but a national-scale bank might.

### 8.1 MongoDB shard keys, measured on the real data

`shard-key-analysis.js` simulated splitting the 51,658 transaction events across three shards
under three candidate keys, measuring both how evenly all documents spread and where the
newest 5,000 writes land (`shard-key-analysis.png`):

| Candidate shard key | All documents (A / B / C) | Newest 5,000 writes (A / B / C) |
| --- | --- | --- |
| Range on `createdAt` | 56.5 / 43.5 / 0.0 % | 0.0 / 99.7 / 0.3 % |
| Range on `accountId` | 33.4 / 33.4 / 33.2 % | 32.9 / 34.1 / 33.0 % |
| Hashed `accountId` | 34.7 / 30.7 / 34.6 % | 34.5 / 29.9 / 35.6 % |

Range on `createdAt` is the worst choice: one shard sits almost empty (the data stops at the
end of September) and **99.7 % of new writes hit a single shard**, the classic hot-shard
problem seen here in real numbers. Both account-based keys spread the stored data evenly, but a
range on `accountId` would send every newly opened account to the highest range, so **hashed
`accountId`** is the safer key because it spreads new writes as well as old data.

`ledger.accountId` cannot be a shard key because it is an array field; a transaction's
`transfer.fromAccount`, or a top-level `primaryAccountId` copied onto each event, would be used
instead.

### 8.2 PostgreSQL

PostgreSQL can be distributed with the **Citus** extension, sharding `accounts`,
`ledger_entries` and `transfers` by `account_id` and keeping small tables (`account_types`,
`staff`) as **reference tables** copied to every node. The hard case is a **transfer between
accounts on different shards**: it must update two nodes atomically, which needs **two-phase
commit** (slower) or a **saga** (a sequence of local transactions with compensating steps,
like the reversals in Portfolio 3).

## 9. Replicating PostgreSQL (design)

PostgreSQL was run as a single instance in this portfolio. In production, NairaFlow would use:

1. **Streaming replication** to one or more **hot standbys** (read-only copies kept in sync
   from the write-ahead log), with automatic failover managed by a tool such as Patroni, or
   by a managed service such as Azure Database for PostgreSQL or Amazon RDS.
2. **Logical replication or change data capture** (for example Debezium) to stream changes
   from PostgreSQL into MongoDB. This fixes the "stale snapshot" risk identified in
   Portfolio 4, where MongoDB balances only reflect the moment of export.

## 10. Cloud deployment and security

| Control | Observed in this portfolio | Production recommendation |
| --- | --- | --- |
| **Network access** | Atlas IP access list rejected my connection (TLS error) whenever my IP changed | Private networking (VPC peering / private endpoints); no public access |
| **Encryption in transit** | All Compass connections used TLS | Enforce TLS 1.2+ everywhere |
| **Encryption at rest** | Provided by Atlas | Customer-managed keys for regulated data |
| **Least privilege** | Database user was created with Atlas Admin | Separate app user with `readWrite` on `nairaflow` only |
| **Sensitive fields** | BVNs stored in plain text (fictional data) | Field-level encryption (e.g. Queryable Encryption) |
| **Backups** | Free tier has no automated backups | Continuous backup with point-in-time recovery |
| **Data location** | Paris – the nearest free region | Check Nigerian data-protection and banking-regulator requirements on where customer data may be stored; consider an African region |

Under the **shared responsibility model**, the provider secures the infrastructure; NairaFlow
remains responsible for network rules, users, roles, encryption keys and its own data.

## 11. Limitations

- The free tier does not allow failover to be triggered on demand; failover was observed
  rather than tested.
- Sharding is measured on exported data but not run on a live sharded cluster; PostgreSQL replication is designed, not implemented.
- All servers are in one region, so cross-region latency was not measured.
- Timings were taken from a single location and network.