-- ===========================================================================
-- capture_plans.sql: measure every workload query and save its plan.
--
--   BEFORE the indexes:  psql -U postgres -d ecommerce -v phase=before -f capture_plans.sql
--   AFTER  the indexes:  psql -U postgres -d ecommerce -v phase=after  -f capture_plans.sql
--
-- Run it from this folder. It writes:
--   plans/<phase>/q1.txt ... q7.txt   the plan of the MEDIAN run, plus all 3 times
--   plans/<phase>/summary.csv         median time, scan types and buffers per query
--
-- Method: each query is run 3 times with EXPLAIN (ANALYZE, BUFFERS) and the
-- median (middle) time is kept (see bench_helper.sql). The query text below is
-- the same as in queries.sql.
-- ===========================================================================
\set ON_ERROR_STOP on
\pset pager off
\if :{?phase}
\else
  \echo 'Please run with -v phase=before or -v phase=after'
  \quit
\endif

\i bench_helper.sql

INSERT INTO runs SELECT 'q1', 'Q1: Show one customer''s last 20 orders, newest first.', $q$SELECT order_id, order_date, status, total_amount
FROM orders
WHERE customer_id = 10
ORDER BY order_date DESC
LIMIT 20;$q$, b.* FROM pg_temp.bench($q$SELECT order_id, order_date, status, total_amount
FROM orders
WHERE customer_id = 10
ORDER BY order_date DESC
LIMIT 20;$q$) b;
INSERT INTO runs SELECT 'q2', 'Q2: Find orders that have been PENDING for more than 2 days.', $q$SELECT order_id, customer_id, order_date, total_amount
FROM orders
WHERE status = 'PENDING'
  AND order_date < TIMESTAMPTZ '2026-10-15' - INTERVAL '2 days'
ORDER BY order_date;$q$, b.* FROM pg_temp.bench($q$SELECT order_id, customer_id, order_date, total_amount
FROM orders
WHERE status = 'PENDING'
  AND order_date < TIMESTAMPTZ '2026-10-15' - INTERVAL '2 days'
ORDER BY order_date;$q$) b;
INSERT INTO runs SELECT 'q3', 'Q3: List the items one seller sold in the last 30 days (cancelled orders excluded).', $q$SELECT o.order_id, o.order_date, p.name AS product, oi.quantity,
       oi.unit_price * oi.quantity AS line_total
FROM order_items oi
JOIN orders   o ON o.order_id   = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE oi.seller_id = 33
  AND o.order_date >= TIMESTAMPTZ '2026-10-15' - INTERVAL '30 days'
  AND o.status <> 'CANCELLED'
ORDER BY o.order_date DESC;$q$, b.* FROM pg_temp.bench($q$SELECT o.order_id, o.order_date, p.name AS product, oi.quantity,
       oi.unit_price * oi.quantity AS line_total
FROM order_items oi
JOIN orders   o ON o.order_id   = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE oi.seller_id = 33
  AND o.order_date >= TIMESTAMPTZ '2026-10-15' - INTERVAL '30 days'
  AND o.status <> 'CANCELLED'
ORDER BY o.order_date DESC;$q$) b;
INSERT INTO runs SELECT 'q4', 'Q4: Find the top 10 best-selling products in the last 90 days.', $q$SELECT p.product_id, p.name, SUM(oi.quantity) AS units_sold
FROM order_items oi
JOIN orders   o ON o.order_id   = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_date >= TIMESTAMPTZ '2026-10-15' - INTERVAL '90 days'
  AND o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
GROUP BY p.product_id, p.name
ORDER BY units_sold DESC
LIMIT 10;$q$, b.* FROM pg_temp.bench($q$SELECT p.product_id, p.name, SUM(oi.quantity) AS units_sold
FROM order_items oi
JOIN orders   o ON o.order_id   = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_date >= TIMESTAMPTZ '2026-10-15' - INTERVAL '90 days'
  AND o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
GROUP BY p.product_id, p.name
ORDER BY units_sold DESC
LIMIT 10;$q$) b;
INSERT INTO runs SELECT 'q5', 'Q5: Calculate the monthly commission earned from each seller.', $q$SELECT oi.seller_id,
       DATE_TRUNC('month', o.order_date) AS month,
       ROUND(SUM(oi.unit_price * oi.quantity * oi.commission_rate), 2) AS commission
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
WHERE o.status = 'DELIVERED'
GROUP BY oi.seller_id, DATE_TRUNC('month', o.order_date)
ORDER BY oi.seller_id, month;$q$, b.* FROM pg_temp.bench($q$SELECT oi.seller_id,
       DATE_TRUNC('month', o.order_date) AS month,
       ROUND(SUM(oi.unit_price * oi.quantity * oi.commission_rate), 2) AS commission
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
WHERE o.status = 'DELIVERED'
GROUP BY oi.seller_id, DATE_TRUNC('month', o.order_date)
ORDER BY oi.seller_id, month;$q$) b;
INSERT INTO runs SELECT 'q6', 'Q6: Find the riders with the most FAILED deliveries.', $q$SELECT r.rider_id, r.full_name, COUNT(*) AS failed_deliveries
FROM deliveries d
JOIN riders r ON r.rider_id = d.rider_id
WHERE d.status = 'FAILED'
GROUP BY r.rider_id, r.full_name
ORDER BY failed_deliveries DESC
LIMIT 10;$q$, b.* FROM pg_temp.bench($q$SELECT r.rider_id, r.full_name, COUNT(*) AS failed_deliveries
FROM deliveries d
JOIN riders r ON r.rider_id = d.rider_id
WHERE d.status = 'FAILED'
GROUP BY r.rider_id, r.full_name
ORDER BY failed_deliveries DESC
LIMIT 10;$q$) b;
INSERT INTO runs SELECT 'q7', 'Q7: Show one customer''s wallet history, newest first.', $q$SELECT created_at, type, reason, amount, order_id
FROM wallet_transactions
WHERE customer_id = 10
ORDER BY created_at DESC;$q$, b.* FROM pg_temp.bench($q$SELECT created_at, type, reason, amount, order_id
FROM wallet_transactions
WHERE customer_id = 10
ORDER BY created_at DESC;$q$) b;

CREATE TEMP TABLE bench_summary AS
SELECT substr(m.label, 2)::integer AS qno,
       m.median_ms,
       COALESCE((SELECT string_agg(DISTINCT x[1] || COALESCE(' [' || x[2] || ']', '') || ' on ' || x[3], '; ')
                 FROM regexp_matches(m.plan,
                      '((?:Parallel )?(?:Seq Scan|Index Only Scan|Index Scan|Bitmap Heap Scan|Bitmap Index Scan))(?: using (\w+))? on (\w+)',
                      'g') AS x), 'none') AS scans,
       COALESCE((regexp_match(substring(m.plan from 'Buffers: shared [^\n]*'), 'hit=(\d+)'))[1]::bigint, 0)
     + COALESCE((regexp_match(substring(m.plan from 'Buffers: shared [^\n]*'), 'read=(\d+)'))[1]::bigint, 0) AS buffers
FROM median_runs m;

\pset tuples_only on
\pset format unaligned
\o plans/:phase/q1.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'q1';
\o
\o plans/:phase/q2.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'q2';
\o
\o plans/:phase/q3.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'q3';
\o
\o plans/:phase/q4.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'q4';
\o
\o plans/:phase/q5.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'q5';
\o
\o plans/:phase/q6.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'q6';
\o
\o plans/:phase/q7.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'q7';
\o

\o plans/:phase/summary.csv
COPY (SELECT qno, median_ms, scans, buffers FROM bench_summary ORDER BY qno) TO STDOUT WITH CSV HEADER;
\o

-- what you see on screen (screenshot this)
\pset tuples_only off
\pset format aligned
SELECT qno AS q, median_ms AS "median ms", buffers, scans AS "scan types"
FROM bench_summary ORDER BY qno;
DROP TABLE bench_summary;
