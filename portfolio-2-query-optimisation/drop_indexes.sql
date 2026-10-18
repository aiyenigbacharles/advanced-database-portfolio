-- ===========================================================================
-- drop_indexes.sql: removes every index created by indexes.sql, so the
-- database goes back to the "before" state (only primary and unique keys).
-- ===========================================================================
\set ON_ERROR_STOP on

DROP INDEX IF EXISTS idx_wallet_customer_date;
DROP INDEX IF EXISTS idx_deliveries_failed_rider;
DROP INDEX IF EXISTS idx_order_items_seller_order;
DROP INDEX IF EXISTS idx_orders_pending_date;
DROP INDEX IF EXISTS idx_orders_customer_date;

ANALYZE orders;
ANALYZE order_items;
ANALYZE deliveries;
ANALYZE wallet_transactions;
