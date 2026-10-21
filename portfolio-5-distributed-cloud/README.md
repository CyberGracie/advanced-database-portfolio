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

## How to reproduce

1. Connect to the Atlas cluster in MongoDB Compass and open the MongoDB shell.
2. Run `use("nairaflow")`, then each block in `replication-tests.js` one at a time.
3. Always reset to `setReadPref("primary")` after the secondary-read test.