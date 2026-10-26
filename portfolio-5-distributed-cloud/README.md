# Portfolio 5: Distributed and Cloud Databases

**Case study:** NairaFlow Digital Bank<br>
**Platform:** MongoDB Atlas (free tier, MongoDB 8.0.34), three-node replica set on AWS eu-west-3 (Paris)

## Summary

NairaFlow's MongoDB database runs on a cloud-hosted, three-server **replica set**. Tests show
which server is primary, that reads can be served by a secondary, and how write concerns
trade durability for latency. A **real automatic failover** was captured: the primary moved
from `shard-00-02` to `shard-00-01` between 18 and 21 October with no interruption. The
write-up covers consistency (CAP), sharding, PostgreSQL replication and cloud security.

Full write-up: **[distributed-design.md](distributed-design.md)**

## Contents

| File | Purpose |
| --- | --- |
| [replication-tests.js](replication-tests.js) | Replica set summary, read preferences, write concerns, majority read |
| [distributed-design.md](distributed-design.md) | Results, failover, CAP trade-offs, sharding design, cloud security |
| [transaction-test.js](transaction-test.js) | Multi-document transfer transaction: commit, abort, isolation |
| [shard-key-analysis.js](shard-key-analysis.js) | Three candidate shard keys measured on the real data |
| [screenshots/](screenshots/) | Evidence for every test |

## Key results

| Test | Result |
| --- | --- |
| Topology | 3 servers: 1 primary, 2 secondaries (`atlas-6ht26w-shard-0`) |
| Failover | Primary changed from `shard-00-02` (18 Oct) to `shard-00-01` (21 Oct) automatically |
| Read preference | `primary` served by `shard-00-01`; `secondary` served by `shard-00-00` |
| Write concerns | `w:1` 117 ms, `w:majority` 121 ms, `w:3` 116 ms (median of 15): no meaningful difference within one region |
| Impossible write concern | `w:5` rejected: *Not enough data-bearing nodes* |
| Recommendation | `w:"majority"` and majority reads for all money movement |
| Multi-document transaction | A transfer commits or aborts atomically; an uncommitted change is invisible to other readers |
| Shard key | Range on `createdAt` sends 99.7% of new writes to one shard; hashed `accountId` spreads evenly |

## Evidence

| Screenshot (`screenshots/`) | What it shows |
| --- | --- |
| `atlas-replica-set-hello.png` | 18 October: three hosts, primary `shard-00-02` |
| `a-atlas-nodes.png`, `a-replica-set-summary.png` | 21 October: primary is now `shard-00-01` (failover) |
| `b1-read-from-primary.png` | Primary read served by `shard-00-01` |
| `b2-read-from-secondary.png` | Secondary read served by `shard-00-00` |
| `c1-write-concern-timings.png` | Median insert times for `w:1`, `w:"majority"` and `w:3` |
| `c2-unsatisfiable-write-concern.png` | `w:5` rejected: *Not enough data-bearing nodes* |
| `c3-majority-read.png`, `c2-c3-c4-results.png` | Majority read and test clean-up |
| `t1-transaction-commit.png`, `t2-transaction-abort.png`, `t3-transaction-isolation.png` | Multi-document transfer: commit, abort, isolation |
| `shard-key-analysis.png` | Three shard keys measured against the real 51,658 events |

## How to reproduce

1. Connect to the Atlas cluster in MongoDB Compass and open the MongoDB shell.
2. Run `use("nairaflow")`, then each block in `replication-tests.js` one at a time.
3. Always reset to `setReadPref("primary")` after the secondary-read test.