# Portfolio 2: Query Processing and Optimisation

**Case study:** NairaFlow Digital Bank<br>
**DBMS:** PostgreSQL 18 (pgAdmin 4)<br>
**Data:** 502,000 transactions, ~772,000 ledger entries (from Portfolio 1 `seed.sql`)

## Summary

Six business queries were measured before and after adding four targeted indexes.
Selective queries became **330–725× faster**; bulk aggregations did not benefit, and an
experiment forcing an index plan showed why. The indexes roughly doubled ledger insert time.

| Query | Before (ms) | After (ms) | Change |
| --- | --- | --- | --- |
| Q1 Account statement | 353.944 | 0.488 | ~725× faster |
| Q2 Failed transfers (1 day) | 216.375 | 0.656 | ~330× faster |
| Q3 Top 10 customers | 621.821 | 778.384 | No index used |
| Q4 Daily totals | 366.663 | 92.998 | ~3.9× faster |
| Q5 Balance reconciliation | 564.719 | 761.616 | No index used |
| Q6 Suspicious activity | 278.890 | 117.848 | ~2.4× faster |

Full analysis: **[analysis.md](analysis.md)**

## Contents

| File | Purpose |
| --- | --- |
| [queries.sql](queries.sql) | The six business queries (Q1–Q6) |
| [indexes.sql](indexes.sql) | The four indexes, each with its rationale |
| [write-cost-test.sql](write-cost-test.sql) | Insert test used to measure index write cost |
| [timings.md](timings.md) | Raw timings: three runs per query, before and after |
| [plans/before](plans/before) | Execution plans with no extra indexes |
| [plans/after](plans/after) | Execution plans with indexes, plus the forced-index experiment |
| [analysis.md](analysis.md) | Findings, costs, recommendations and limitations |
| [screenshots/](screenshots/) | Query results, plans and index sizes |

## Evidence

| Screenshot (`screenshots/`) | What it shows |
| --- | --- |
| `q1-result.png` … `q6-result.png` | Results of each business query |
| `q1-plan-before.png`, `q2-plan-before.png` | Parallel sequential scans before indexing (hundreds of thousands of rows removed by filter) |
| `q1-plan-after.png` … `q6-plan-after.png` | Plans after indexing: index scans for Q1/Q2, index-only and bitmap scans for Q4/Q6, unchanged plans for Q3/Q5 |
| `index-sizes.png` | Size of each index (partial index I2 = 344 kB) |

Full text plans are in `plans/before/` and `plans/after/`, including `q5-forced-index-plan.txt`.

## How to reproduce

1. Build the database with Portfolio 1 (`schema.sql` → `seed.sql` → `audit-triggers.sql`).
2. Run each query in `queries.sql` with `EXPLAIN (ANALYZE, BUFFERS)` three times; record the median.
3. Run `VACUUM ANALYZE;`, then `indexes.sql`.
4. Repeat step 2.
5. Run `write-cost-test.sql` before and after step 3 (auto-commit off; finish with `ROLLBACK`).