-- ===========================================================================
-- index_costs.sql: what the indexes cost.
-- 1. Disk size (pg_relation_size) of every index and table.
-- 2. Write cost: how long it takes to insert 50,000 orders into a temporary
--    copy of the orders table. Run it once WITHOUT the new indexes and once WITH.
--      psql -U postgres -d ecommerce -f index_costs.sql
-- ===========================================================================
\set ON_ERROR_STOP on
\pset pager off

-- 1. size on disk
SELECT c.relname AS name, CASE c.relkind WHEN 'r' THEN 'table' ELSE 'index' END AS kind,
       pg_size_pretty(pg_relation_size(c.oid)) AS size,
       pg_relation_size(c.oid) AS bytes
FROM pg_class c
WHERE c.relname IN ('orders', 'order_items', 'deliveries', 'wallet_transactions',
                    'orders_pkey', 'order_items_pkey', 'uq_order_items_order_product',
                    'idx_orders_customer_date', 'idx_orders_pending_date',
                    'idx_order_items_seller_order', 'idx_deliveries_failed_rider',
                    'idx_wallet_customer_date')
ORDER BY kind DESC, bytes DESC;

SELECT count(*) AS extra_indexes,
       pg_size_pretty(COALESCE(sum(pg_relation_size(indexrelid)), 0)) AS total_size_of_extra_indexes
FROM pg_stat_user_indexes WHERE indexrelname LIKE 'idx\_%';

-- 2. write cost: three timed runs.
-- The rows go into a TEMP COPY of orders (same columns, same indexes), so the
-- real orders table and its id counter are never touched. The copy has the
-- primary key plus whichever extra indexes exist right now, which is exactly
-- what we want to compare.
DROP TABLE IF EXISTS pg_temp.orders_copy, pg_temp.write_runs;
CREATE TEMP TABLE orders_copy (LIKE orders INCLUDING ALL);
CREATE TEMP TABLE write_runs (run_no integer, ms numeric);

DO $$
DECLARE
    t0 timestamptz;
    i  integer;
BEGIN
    FOR i IN 1..3 LOOP
        t0 := clock_timestamp();
        INSERT INTO orders_copy (customer_id, address_id, order_date, status, total_amount)
        SELECT customer_id, address_id, order_date, status, total_amount
        FROM orders ORDER BY order_id LIMIT 50000;
        INSERT INTO write_runs VALUES (i, round(extract(epoch FROM clock_timestamp() - t0) * 1000));
        TRUNCATE orders_copy;
    END LOOP;
END
$$;

-- time to insert 50,000 orders, 3 runs and the median
SELECT (SELECT string_agg(ms::text, ', ' ORDER BY run_no) FROM write_runs) AS "3 runs (ms)",
       (SELECT ms FROM write_runs ORDER BY ms OFFSET 1 LIMIT 1)            AS "median ms";
