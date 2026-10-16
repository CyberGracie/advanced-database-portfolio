# Execution times (ms) – median of 3 runs

| Query | Before: run 1 | Run 2 | Run 3 | **Before median** | After: run 1 | Run 2 | Run 3 | **After median** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Q1 Account statement | 353.944|487.366|305.196|353.944 | | | | |
| Q2 Failed transfers (1 day) |216.375|206.076|222.431|216.375| | | | |
| Q3 Top 10 customers |837.386|562.880|621.821|621.821| | | | |
| Q4 Daily totals |366.663|423.886|332.192|366.663| | | | |
| Q5 Balance reconciliation |674.672|564.719|552.279|564.719| | | | |
| Q6 Suspicious activity |291.797|231.687|278.890|278.890| | | | |

**Control (after VACUUM ANALYZE, no indexes):** Q1 = 341.660 ms<br>
**Write test (50,000 ledger inserts), before indexes:** 1,947.782 ms