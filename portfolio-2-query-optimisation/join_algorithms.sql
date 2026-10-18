-- ===========================================================================
-- join_algorithms.sql: Nested Loop vs Hash Join vs Merge Join on the same query.
--   psql -U postgres -d ecommerce -f join_algorithms.sql
-- Each variant is run 3 times and the median is kept. Plans are saved in
-- plans/join-algorithms/.
--
-- PostgreSQL normally picks the join algorithm itself. To compare them we make
-- the other two look impossible with SET enable_xxx = off. These settings only
-- last for this session, and RESET puts everything back after each test.
-- Parallel workers are switched off so the plans are easy to read and compare.
--
--   Nested Loop: for each row of the outer table, look up matches in the inner
--                table (best when the outer side is tiny and there is an index).
--   Hash Join:   build an in-memory hash table of one side, then probe it with
--                the other (best for big, unsorted inputs; needs memory).
--   Merge Join:  sort both sides on the join key and walk them together (best
--                when both sides are already sorted, e.g. from an index).
-- ===========================================================================
\set ON_ERROR_STOP on
\pset pager off
\i bench_helper.sql
SET max_parallel_workers_per_gather = 0;

-- ---------------------------------------------------------------------------
-- J1: one customer's orders with their items (a SMALL join: 28 orders)
-- ---------------------------------------------------------------------------

-- the planner's own choice
INSERT INTO runs SELECT 'small_default', 'J1: one customer''s orders with their items (a SMALL join: 28 orders) - the planner''s own choice', $q$SELECT o.order_id, o.order_date, oi.product_id, oi.quantity
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.customer_id = 10;$q$, b.* FROM pg_temp.bench($q$SELECT o.order_id, o.order_date, oi.product_id, oi.quantity
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.customer_id = 10;$q$) b;
RESET enable_nestloop; RESET enable_hashjoin; RESET enable_mergejoin;

-- forced Nested Loop
SET enable_hashjoin = off; SET enable_mergejoin = off;
INSERT INTO runs SELECT 'small_nestedloop', 'J1: one customer''s orders with their items (a SMALL join: 28 orders) - forced Nested Loop', $q$SELECT o.order_id, o.order_date, oi.product_id, oi.quantity
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.customer_id = 10;$q$, b.* FROM pg_temp.bench($q$SELECT o.order_id, o.order_date, oi.product_id, oi.quantity
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.customer_id = 10;$q$) b;
RESET enable_nestloop; RESET enable_hashjoin; RESET enable_mergejoin;

-- forced Hash Join
SET enable_nestloop = off; SET enable_mergejoin = off;
INSERT INTO runs SELECT 'small_hashjoin', 'J1: one customer''s orders with their items (a SMALL join: 28 orders) - forced Hash Join', $q$SELECT o.order_id, o.order_date, oi.product_id, oi.quantity
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.customer_id = 10;$q$, b.* FROM pg_temp.bench($q$SELECT o.order_id, o.order_date, oi.product_id, oi.quantity
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.customer_id = 10;$q$) b;
RESET enable_nestloop; RESET enable_hashjoin; RESET enable_mergejoin;

-- forced Merge Join
SET enable_nestloop = off; SET enable_hashjoin = off;
INSERT INTO runs SELECT 'small_mergejoin', 'J1: one customer''s orders with their items (a SMALL join: 28 orders) - forced Merge Join', $q$SELECT o.order_id, o.order_date, oi.product_id, oi.quantity
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.customer_id = 10;$q$, b.* FROM pg_temp.bench($q$SELECT o.order_id, o.order_date, oi.product_id, oi.quantity
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.customer_id = 10;$q$) b;
RESET enable_nestloop; RESET enable_hashjoin; RESET enable_mergejoin;

-- ---------------------------------------------------------------------------
-- J2: item revenue for every order in the last 90 days (a LARGE join: about 52,000 orders)
-- ---------------------------------------------------------------------------

-- the planner's own choice
INSERT INTO runs SELECT 'large_default', 'J2: item revenue for every order in the last 90 days (a LARGE join: about 52,000 orders) - the planner''s own choice', $q$SELECT COUNT(*) AS items, SUM(oi.unit_price * oi.quantity) AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_date >= TIMESTAMPTZ '2026-10-15' - INTERVAL '90 days';$q$, b.* FROM pg_temp.bench($q$SELECT COUNT(*) AS items, SUM(oi.unit_price * oi.quantity) AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_date >= TIMESTAMPTZ '2026-10-15' - INTERVAL '90 days';$q$) b;
RESET enable_nestloop; RESET enable_hashjoin; RESET enable_mergejoin;

-- forced Nested Loop
SET enable_hashjoin = off; SET enable_mergejoin = off;
INSERT INTO runs SELECT 'large_nestedloop', 'J2: item revenue for every order in the last 90 days (a LARGE join: about 52,000 orders) - forced Nested Loop', $q$SELECT COUNT(*) AS items, SUM(oi.unit_price * oi.quantity) AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_date >= TIMESTAMPTZ '2026-10-15' - INTERVAL '90 days';$q$, b.* FROM pg_temp.bench($q$SELECT COUNT(*) AS items, SUM(oi.unit_price * oi.quantity) AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_date >= TIMESTAMPTZ '2026-10-15' - INTERVAL '90 days';$q$) b;
RESET enable_nestloop; RESET enable_hashjoin; RESET enable_mergejoin;

-- forced Hash Join
SET enable_nestloop = off; SET enable_mergejoin = off;
INSERT INTO runs SELECT 'large_hashjoin', 'J2: item revenue for every order in the last 90 days (a LARGE join: about 52,000 orders) - forced Hash Join', $q$SELECT COUNT(*) AS items, SUM(oi.unit_price * oi.quantity) AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_date >= TIMESTAMPTZ '2026-10-15' - INTERVAL '90 days';$q$, b.* FROM pg_temp.bench($q$SELECT COUNT(*) AS items, SUM(oi.unit_price * oi.quantity) AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_date >= TIMESTAMPTZ '2026-10-15' - INTERVAL '90 days';$q$) b;
RESET enable_nestloop; RESET enable_hashjoin; RESET enable_mergejoin;

-- forced Merge Join
SET enable_nestloop = off; SET enable_hashjoin = off;
INSERT INTO runs SELECT 'large_mergejoin', 'J2: item revenue for every order in the last 90 days (a LARGE join: about 52,000 orders) - forced Merge Join', $q$SELECT COUNT(*) AS items, SUM(oi.unit_price * oi.quantity) AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_date >= TIMESTAMPTZ '2026-10-15' - INTERVAL '90 days';$q$, b.* FROM pg_temp.bench($q$SELECT COUNT(*) AS items, SUM(oi.unit_price * oi.quantity) AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_date >= TIMESTAMPTZ '2026-10-15' - INTERVAL '90 days';$q$) b;
RESET enable_nestloop; RESET enable_hashjoin; RESET enable_mergejoin;

RESET max_parallel_workers_per_gather;

\pset tuples_only on
\pset format unaligned
\o plans/join-algorithms/small_default.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'small_default';
\o
\o plans/join-algorithms/small_nestedloop.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'small_nestedloop';
\o
\o plans/join-algorithms/small_hashjoin.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'small_hashjoin';
\o
\o plans/join-algorithms/small_mergejoin.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'small_mergejoin';
\o
\o plans/join-algorithms/large_default.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'large_default';
\o
\o plans/join-algorithms/large_nestedloop.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'large_nestedloop';
\o
\o plans/join-algorithms/large_hashjoin.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'large_hashjoin';
\o
\o plans/join-algorithms/large_mergejoin.txt
SELECT title || E'\n\n' || query || E'\n\nAll 3 runs (ms): ' || array_to_string(all_ms, ', ')
       || E'\nMedian execution time: ' || median_ms || E' ms\n\n' || plan
FROM median_runs WHERE label = 'large_mergejoin';
\o
\pset tuples_only off
\pset format aligned
-- summary (screenshot this)
SELECT label,
       (regexp_match(plan, '(Nested Loop|Hash Join|Merge Join)'))[1] AS join_used,
       median_ms,
       COALESCE((regexp_match(substring(plan from 'Buffers: shared [^\n]*'), 'hit=(\d+)'))[1]::bigint, 0) AS buffers
FROM median_runs ORDER BY label;
