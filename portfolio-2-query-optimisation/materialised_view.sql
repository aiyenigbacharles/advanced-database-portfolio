-- ===========================================================================
-- materialised_view.sql: Q5 (monthly commission per seller) as a materialised view.
--   psql -U postgres -d ecommerce -f materialised_view.sql
-- Plans and output are saved in plans/matview/.
--
-- Why Q5: an index cannot help it, because it must add up almost every order
-- item. The answer changes slowly (once a month's orders are delivered, that
-- month rarely changes), so it is a good fit for "work it out once, read it
-- many times". A materialised view stores the RESULT of a query as a real table.
-- The catch: it does not update itself. It is stale until REFRESHed.
-- This is the same idea as caching (Redis, later in Portfolio 4), but inside
-- the database.
-- ===========================================================================
\set ON_ERROR_STOP on
\pset pager off
\i bench_helper.sql

DROP MATERIALIZED VIEW IF EXISTS mv_monthly_commission;

-- 1. create it (this runs the slow query once and stores the answer)
\timing on
CREATE MATERIALIZED VIEW mv_monthly_commission AS
SELECT oi.seller_id,
       DATE_TRUNC('month', o.order_date) AS month,
       ROUND(SUM(oi.unit_price * oi.quantity * oi.commission_rate), 2) AS commission
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
WHERE o.status = 'DELIVERED'
GROUP BY oi.seller_id, DATE_TRUNC('month', o.order_date);
\timing off

-- A unique index lets us look up one seller quickly, and is also required for
-- REFRESH MATERIALIZED VIEW CONCURRENTLY (a refresh that does not block readers).
CREATE UNIQUE INDEX idx_mv_commission_seller_month
    ON mv_monthly_commission (seller_id, month);
ANALYZE mv_monthly_commission;

SELECT COUNT(*) AS rows_in_view,
       pg_size_pretty(pg_relation_size('mv_monthly_commission')) AS view_size
FROM mv_monthly_commission;

-- 2. direct query versus reading the view (each run 3 times, median kept)
INSERT INTO runs SELECT 'm1_direct_query', 'Q5 run directly against the tables', $q$SELECT oi.seller_id,
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
INSERT INTO runs SELECT 'm2_read_view', 'Q5 answered by reading the materialised view', $q$SELECT seller_id, month, commission FROM mv_monthly_commission ORDER BY seller_id, month;$q$, b.* FROM pg_temp.bench($q$SELECT seller_id, month, commission FROM mv_monthly_commission ORDER BY seller_id, month;$q$) b;
INSERT INTO runs SELECT 'm3_read_view_one_seller', 'One seller''s monthly commission, from the view (a seller dashboard)', $q$SELECT month, commission FROM mv_monthly_commission WHERE seller_id = 33 ORDER BY month;$q$, b.* FROM pg_temp.bench($q$SELECT month, commission FROM mv_monthly_commission WHERE seller_id = 33 ORDER BY month;$q$) b;

\pset tuples_only on
\pset format unaligned
\o plans/matview/direct_query.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'm1_direct_query';
\o
\o plans/matview/read_view.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'm2_read_view';
\o
\o plans/matview/read_view_one_seller.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'm3_read_view_one_seller';
\o
\pset tuples_only off
\pset format aligned
SELECT label, median_ms, all_ms FROM median_runs ORDER BY label;

-- is the view identical to the direct query? (must return 0 rows)
SELECT 'rows that differ' AS check, COUNT(*) FROM (
    (SELECT oi.seller_id, DATE_TRUNC('month', o.order_date) AS month,
            ROUND(SUM(oi.unit_price * oi.quantity * oi.commission_rate), 2) AS commission
     FROM order_items oi JOIN orders o ON o.order_id = oi.order_id
     WHERE o.status = 'DELIVERED' GROUP BY 1, 2
     EXCEPT SELECT seller_id, month, commission FROM mv_monthly_commission)
    UNION ALL
    (SELECT seller_id, month, commission FROM mv_monthly_commission
     EXCEPT
     SELECT oi.seller_id, DATE_TRUNC('month', o.order_date),
            ROUND(SUM(oi.unit_price * oi.quantity * oi.commission_rate), 2)
     FROM order_items oi JOIN orders o ON o.order_id = oi.order_id
     WHERE o.status = 'DELIVERED' GROUP BY 1, 2)
) d;

-- 3. STALENESS DEMO. Everything below is inside a transaction that is rolled
-- back at the end, so no real data is changed.
-- We change one delivered order item, then compare the live query with the view.
\o plans/matview/staleness_demo.txt
BEGIN;

-- pick one item of a DELIVERED order of seller 33
SELECT oi.order_item_id AS item_id, DATE_TRUNC('month', o.order_date) AS item_month
FROM order_items oi JOIN orders o ON o.order_id = oi.order_id
WHERE oi.seller_id = 33 AND o.status = 'DELIVERED'
ORDER BY oi.order_item_id LIMIT 1 \gset

\qecho 'Seller 33, that item''s month. The view and the live query agree at first:'
SELECT 'view' AS source, commission FROM mv_monthly_commission
WHERE seller_id = 33 AND month = :'item_month'
UNION ALL
SELECT 'live query', ROUND(SUM(oi.unit_price * oi.quantity * oi.commission_rate), 2)
FROM order_items oi JOIN orders o ON o.order_id = oi.order_id
WHERE o.status = 'DELIVERED' AND oi.seller_id = 33 AND DATE_TRUNC('month', o.order_date) = :'item_month';

-- someone changes the quantity of that item
UPDATE order_items SET quantity = quantity + 5 WHERE order_item_id = :item_id;

\qecho 'After the change, the live query moves but the view is STALE:'
SELECT 'view' AS source, commission FROM mv_monthly_commission
WHERE seller_id = 33 AND month = :'item_month'
UNION ALL
SELECT 'live query', ROUND(SUM(oi.unit_price * oi.quantity * oi.commission_rate), 2)
FROM order_items oi JOIN orders o ON o.order_id = oi.order_id
WHERE o.status = 'DELIVERED' AND oi.seller_id = 33 AND DATE_TRUNC('month', o.order_date) = :'item_month';

\timing on
REFRESH MATERIALIZED VIEW mv_monthly_commission;
\timing off

\qecho 'After REFRESH MATERIALIZED VIEW, the view has caught up:'
SELECT 'view' AS source, commission FROM mv_monthly_commission
WHERE seller_id = 33 AND month = :'item_month'
UNION ALL
SELECT 'live query', ROUND(SUM(oi.unit_price * oi.quantity * oi.commission_rate), 2)
FROM order_items oi JOIN orders o ON o.order_id = oi.order_id
WHERE o.status = 'DELIVERED' AND oi.seller_id = 33 AND DATE_TRUNC('month', o.order_date) = :'item_month';

ROLLBACK;
\o

-- show the demo on screen as well
\! cat plans/matview/staleness_demo.txt

-- In real use you would refresh on a schedule (for example every night) with:
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_commission;
-- CONCURRENTLY lets people keep reading the old data while the new data is built.
