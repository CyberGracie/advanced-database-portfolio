# Execution times (ms) – median of 3 runs

| Query | Before: run 1 | Run 2 | Run 3 | **Before median** | After: run 1 | Run 2 | Run 3 | **After median** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Q1 Account statement | 353.944 | 487.366 | 305.196 | **353.944** | 0.535 | 0.488 | 0.409 | **0.488** |
| Q2 Failed transfers (1 day) | 216.375 | 206.076 | 222.431 | **216.375** | 0.679 | 0.603 | 0.656 | **0.656** |
| Q3 Top 10 customers | 837.386 | 562.880 | 621.821 | **621.821** | 778.384 | 709.234 | 904.454 | **778.384** |
| Q4 Daily totals | 366.663 | 423.886 | 332.192 | **366.663** | 60.651 | 118.080 | 92.998 | **92.998** |
| Q5 Balance reconciliation | 674.672 | 564.719 | 552.279 | **564.719** | 761.616 | 835.446 | 750.006 | **761.616** |
| Q6 Suspicious activity | 291.797 | 231.687 | 278.890 | **278.890** | 109.133 | 117.848 | 152.423 | **117.848** |

**Control (after VACUUM ANALYZE, no indexes):** Q1 = 341.660 ms<br>
**Write test (50,000 ledger inserts), before indexes:** 1,947.782 ms<br>
**Write test (50,000 ledger inserts), after indexes:** 3,785.701 ms<br>
**Q5 with index forced (enable_seqscan = off):** 635.763 ms<br>
**Q4 from the materialised view `mv_daily_totals`:** 0.268 ms (vs 92.998 ms with index I3)