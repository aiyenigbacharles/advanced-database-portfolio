-- ===========================================================================
-- indexes.sql: the speed indexes for the workload in queries.sql
-- Undo everything with drop_indexes.sql. Together they make before/after
-- repeatable: drop_indexes.sql -> capture "before" -> indexes.sql -> capture "after".
--
-- The primary keys and UNIQUE constraints from schema.sql already have indexes.
-- These five are the extra ones. Only queries that were slow and that an index
-- can really help get one (Q4 and Q5 read most of the table, so an index would
-- not help them; see materialised_view.sql for those).
-- ===========================================================================
\set ON_ERROR_STOP on
\timing on

-- Q1 (composite index): "one customer's last 20 orders, newest first".
-- Column order matters: customer_id FIRST because the query tests it with =,
-- order_date SECOND because the query sorts by it. All of one customer's orders
-- sit together in the index, already in date order, so PostgreSQL reads only
-- that customer's rows (about 30 page reads instead of all 1,754 pages of the
-- table). It can hand them back already sorted, or sort the few rows itself;
-- the planner picks whichever it estimates is cheaper.
CREATE INDEX IF NOT EXISTS idx_orders_customer_date
    ON orders (customer_id, order_date DESC);

-- Q2 (partial index): "orders PENDING for more than 2 days".
-- Only about 3% of orders are PENDING, so the index only contains those rows.
-- It is much smaller than a full index and cheaper to keep up to date. It is
-- keyed on order_date because the query filters and sorts by date. The query
-- must say status = 'PENDING' (as Q2 does) for PostgreSQL to be allowed to use it.
CREATE INDEX IF NOT EXISTS idx_orders_pending_date
    ON orders (order_date) WHERE status = 'PENDING';

-- Q3 (composite index): "one seller's items sold in the last 30 days".
-- seller_id FIRST because of WHERE seller_id = 33. order_id SECOND because it is
-- the join key to orders, so the join can read it straight from the index.
-- (order_items had no index starting with seller_id, so this query scanned all
-- 250,000 items.)
CREATE INDEX IF NOT EXISTS idx_order_items_seller_order
    ON order_items (seller_id, order_id);

-- Q6 (partial index): "riders with the most FAILED deliveries".
-- Only about 1% of deliveries are FAILED. The index holds just those rows,
-- keyed on rider_id because the query groups by rider. The query needs nothing
-- else from deliveries, so PostgreSQL can answer from the index alone
-- ("Index Only Scan") without touching the table.
CREATE INDEX IF NOT EXISTS idx_deliveries_failed_rider
    ON deliveries (rider_id) WHERE status = 'FAILED';

-- Q7 (composite index): "one customer's wallet history, newest first".
-- Same pattern as Q1: equality column first (customer_id), sort column second.
CREATE INDEX IF NOT EXISTS idx_wallet_customer_date
    ON wallet_transactions (customer_id, created_at DESC);

-- Fresh statistics so the planner knows about the new indexes.
ANALYZE orders;
ANALYZE order_items;
ANALYZE deliveries;
ANALYZE wallet_transactions;
