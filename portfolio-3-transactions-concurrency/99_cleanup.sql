-- ===========================================================================
-- 99_cleanup.sql: removes ALL demo data (customers, products, orders, wallet
-- rows, helper functions and view). Run it when you have finished the demos.
--   psql -U postgres -d ecommerce -f 99_cleanup.sql
-- ===========================================================================
\set ON_ERROR_STOP on
SELECT demo_clear_all() AS status;
DROP VIEW IF EXISTS demo_oversell_check;
DROP VIEW IF EXISTS demo_wallet_check;
DROP FUNCTION IF EXISTS demo_record_sale(integer, integer, integer);
DROP FUNCTION IF EXISTS demo_reset();
DROP FUNCTION IF EXISTS demo_reset_orders();
DROP FUNCTION IF EXISTS demo_reset_wallets();
DROP FUNCTION IF EXISTS demo_reset_products();
DROP FUNCTION IF EXISTS demo_clear_all();
