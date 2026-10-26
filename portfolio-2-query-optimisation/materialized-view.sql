-- =============================================================
-- NairaFlow – Portfolio 2: materialised view for the finance dashboard (Q4)
-- Run ONE block at a time in pgAdmin's Query Tool, after indexes.sql.
-- A materialised view stores the result of a query on disk, so the
-- dashboard reads a few pre-computed rows instead of aggregating
-- ~50,000 transactions every time. The trade-off: it is a snapshot
-- and must be refreshed.
-- =============================================================


-- M1. Create the materialised view: daily totals by type (successful only)
CREATE MATERIALIZED VIEW mv_daily_totals AS
SELECT created_at::date  AS day,
       transaction_type,
       count(*)          AS transaction_count,
       sum(amount)       AS total_amount
FROM transactions
WHERE status = 'SUCCESS'
GROUP BY created_at::date, transaction_type;

-- A unique index is required for REFRESH ... CONCURRENTLY (readers are not blocked)
CREATE UNIQUE INDEX idx_mv_daily_totals ON mv_daily_totals (day, transaction_type);

ANALYZE mv_daily_totals;


-- M2. Correctness: the view must return exactly what the live query returns
--     for September 2026. Both directions must return 0 rows.
(SELECT day, transaction_type, transaction_count, total_amount
 FROM mv_daily_totals
 WHERE day >= '2026-09-01' AND day < '2026-10-01')
EXCEPT
(SELECT created_at::date, transaction_type, count(*), sum(amount)
 FROM transactions
 WHERE status = 'SUCCESS' AND created_at >= '2026-09-01' AND created_at < '2026-10-01'
 GROUP BY created_at::date, transaction_type);

(SELECT created_at::date, transaction_type, count(*), sum(amount)
 FROM transactions
 WHERE status = 'SUCCESS' AND created_at >= '2026-09-01' AND created_at < '2026-10-01'
 GROUP BY created_at::date, transaction_type)
EXCEPT
(SELECT day, transaction_type, transaction_count, total_amount
 FROM mv_daily_totals
 WHERE day >= '2026-09-01' AND day < '2026-10-01');


-- M3. Timing: Q4 answered from the view (run 3 times, record the median)
EXPLAIN (ANALYZE, BUFFERS)
SELECT day, transaction_type, transaction_count, total_amount
FROM mv_daily_totals
WHERE day >= '2026-09-01' AND day < '2026-10-01'
ORDER BY day, transaction_type;


-- M4. Staleness: a new deposit is NOT in the view until it is refreshed
SELECT deposit_funds(2003, 500);

SELECT 'live table' AS source, count(*) AS deposits_today
FROM transactions
WHERE status = 'SUCCESS' AND transaction_type = 'DEPOSIT' AND created_at::date = current_date
UNION ALL
SELECT 'materialised view', coalesce(sum(transaction_count), 0)
FROM mv_daily_totals
WHERE transaction_type = 'DEPOSIT' AND day = current_date;
-- Expected: live table >= 1, materialised view = 0 (stale)


-- M5. Refresh (note the time in the Messages tab), then re-run the M4 check
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_totals;
-- After refresh both rows of the M4 check should show the same number.
