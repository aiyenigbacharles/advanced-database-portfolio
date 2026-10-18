-- ===========================================================================
-- rewrites.sql: two "bad query / good query" pairs. Same answer, different plan.
--   psql -U postgres -d ecommerce -f rewrites.sql
-- Each query is run 3 times and the median is kept (bench_helper.sql).
-- Plans are saved in plans/rewrites/.
-- Run indexes.sql first (rewrite 2 uses idx_orders_customer_date).
-- ===========================================================================
\set ON_ERROR_STOP on
\pset pager off
\i bench_helper.sql

-- ---------------------------------------------------------------------------
-- Rewrite 1: a function on the column versus a range
-- Question: how many orders were placed on 10 October 2026, and for how much?
--
-- Bad:  WHERE order_date::date = '2026-10-10'
--   The ::date cast is applied to every row's order_date, then compared. An index
--   on order_date is sorted by the ORIGINAL timestamps, not by the dates the cast
--   produces, so PostgreSQL cannot use it to jump to the right rows. It has to
--   read the whole table.
-- Good: WHERE order_date >= '2026-10-10' AND order_date < '2026-10-11'
--   The column is left alone, so the index can find the start of the range and
--   read only that day's rows.
--
-- This experiment needs an index on order_date, which no workload query uses, so
-- it is created here and dropped again right after.
-- ---------------------------------------------------------------------------
CREATE INDEX idx_orders_date_experiment ON orders (order_date);
ANALYZE orders;
INSERT INTO runs SELECT 'r1_bad_cast', 'Rewrite 1, BAD: cast on the column', $q$SELECT COUNT(*), SUM(total_amount) FROM orders
WHERE order_date::date = DATE '2026-10-10';$q$, b.* FROM pg_temp.bench($q$SELECT COUNT(*), SUM(total_amount) FROM orders
WHERE order_date::date = DATE '2026-10-10';$q$) b;
INSERT INTO runs SELECT 'r1_good_range', 'Rewrite 1, GOOD: plain range on the column', $q$SELECT COUNT(*), SUM(total_amount) FROM orders
WHERE order_date >= TIMESTAMPTZ '2026-10-10' AND order_date < TIMESTAMPTZ '2026-10-11';$q$, b.* FROM pg_temp.bench($q$SELECT COUNT(*), SUM(total_amount) FROM orders
WHERE order_date >= TIMESTAMPTZ '2026-10-10' AND order_date < TIMESTAMPTZ '2026-10-11';$q$) b;
DROP INDEX idx_orders_date_experiment;
ANALYZE orders;

-- Same answer? Both rows must show the same count and sum.
SELECT 'bad (cast)' AS version, COUNT(*), SUM(total_amount) FROM orders WHERE order_date::date = DATE '2026-10-10'
UNION ALL
SELECT 'good (range)', COUNT(*), SUM(total_amount) FROM orders
WHERE order_date >= TIMESTAMPTZ '2026-10-10' AND order_date < TIMESTAMPTZ '2026-10-11';

-- ---------------------------------------------------------------------------
-- Rewrite 2: a correlated subquery versus a join
-- Question: which orders are bigger than that customer's own average order?
--
-- Bad:  the subquery mentions o.customer_id from the outer query, so it has to be
--   worked out again for EVERY order: 100,000 separate little aggregates (each
--   uses the customer index, but 100,000 index lookups still add up).
-- Good: work out every customer's average ONCE (GROUP BY), then JOIN it to the
--   orders. One pass over the table, then a join.
-- (Without idx_orders_customer_date the bad version would scan the whole orders
-- table 100,000 times, so it is only run here with the index in place.)
-- ---------------------------------------------------------------------------
INSERT INTO runs SELECT 'r2_bad_correlated', 'Rewrite 2, BAD: correlated subquery', $q$SELECT o.order_id, o.customer_id, o.total_amount
FROM orders o
WHERE o.total_amount > (SELECT AVG(o2.total_amount)
                        FROM orders o2
                        WHERE o2.customer_id = o.customer_id);$q$, b.* FROM pg_temp.bench($q$SELECT o.order_id, o.customer_id, o.total_amount
FROM orders o
WHERE o.total_amount > (SELECT AVG(o2.total_amount)
                        FROM orders o2
                        WHERE o2.customer_id = o.customer_id);$q$) b;
INSERT INTO runs SELECT 'r2_good_join', 'Rewrite 2, GOOD: aggregate once, then join', $q$SELECT o.order_id, o.customer_id, o.total_amount
FROM orders o
JOIN (SELECT customer_id, AVG(total_amount) AS avg_total
      FROM orders GROUP BY customer_id) a ON a.customer_id = o.customer_id
WHERE o.total_amount > a.avg_total;$q$, b.* FROM pg_temp.bench($q$SELECT o.order_id, o.customer_id, o.total_amount
FROM orders o
JOIN (SELECT customer_id, AVG(total_amount) AS avg_total
      FROM orders GROUP BY customer_id) a ON a.customer_id = o.customer_id
WHERE o.total_amount > a.avg_total;$q$) b;

-- Same answer? Both lists must be identical, so this returns 0.
SELECT 'rows that differ between bad and good' AS check, COUNT(*) FROM (
    (SELECT o.order_id FROM orders o
     WHERE o.total_amount > (SELECT AVG(o2.total_amount) FROM orders o2 WHERE o2.customer_id = o.customer_id)
     EXCEPT
     SELECT o.order_id FROM orders o
     JOIN (SELECT customer_id, AVG(total_amount) AS avg_total FROM orders GROUP BY customer_id) a
          ON a.customer_id = o.customer_id WHERE o.total_amount > a.avg_total)
    UNION ALL
    (SELECT o.order_id FROM orders o
     JOIN (SELECT customer_id, AVG(total_amount) AS avg_total FROM orders GROUP BY customer_id) a
          ON a.customer_id = o.customer_id WHERE o.total_amount > a.avg_total
     EXCEPT
     SELECT o.order_id FROM orders o
     WHERE o.total_amount > (SELECT AVG(o2.total_amount) FROM orders o2 WHERE o2.customer_id = o.customer_id))
) d;

\pset tuples_only on
\pset format unaligned
\o plans/rewrites/r1_bad_cast.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'r1_bad_cast';
\o
\o plans/rewrites/r1_good_range.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'r1_good_range';
\o
\o plans/rewrites/r2_bad_correlated.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'r2_bad_correlated';
\o
\o plans/rewrites/r2_good_join.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'r2_good_join';
\o
\pset tuples_only off
\pset format aligned
-- summary (screenshot this)
SELECT label, median_ms, all_ms FROM median_runs ORDER BY label;
