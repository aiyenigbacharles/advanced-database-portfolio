-- ===========================================================================
-- compare.sql: before/after comparison table.
-- Needs plans/before/summary.csv and plans/after/summary.csv, which
-- capture_plans.sql writes. Run from this folder:
--   psql -U postgres -d ecommerce -f compare.sql
-- ===========================================================================
\set ON_ERROR_STOP on
\pset pager off

DROP TABLE IF EXISTS pg_temp.sum_before, pg_temp.sum_after;
CREATE TEMP TABLE sum_before (qno integer, median_ms numeric, scans text, buffers bigint);
CREATE TEMP TABLE sum_after  (qno integer, median_ms numeric, scans text, buffers bigint);
\copy sum_before FROM 'plans/before/summary.csv' CSV HEADER
\copy sum_after  FROM 'plans/after/summary.csv'  CSV HEADER

-- timings and buffers
SELECT 'Q' || b.qno                                   AS query,
       b.median_ms                                    AS before_ms,
       a.median_ms                                    AS after_ms,
       round(b.median_ms / NULLIF(a.median_ms, 0), 1) AS "times faster",
       b.buffers                                      AS buffers_before,
       a.buffers                                      AS buffers_after
FROM sum_before b JOIN sum_after a USING (qno)
ORDER BY b.qno;

-- how each query was answered
SELECT 'Q' || b.qno AS query, b.scans AS scan_before, a.scans AS scan_after
FROM sum_before b JOIN sum_after a USING (qno)
ORDER BY b.qno;
