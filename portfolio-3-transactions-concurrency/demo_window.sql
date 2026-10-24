-- ===========================================================================
-- demo_window.sql: run this in EACH of your two psql windows before a demo:
--   \i demo_window.sql
-- It (1) makes the prompt show which window you are in and whether you are
-- inside a transaction, (2) shows full error codes such as 40001 and 40P01,
-- and (3) remembers the demo customer and product ids as short names.
--
-- Prompt:  W1 ecommerce=#   no transaction open
--          W1 ecommerce=*#  you are INSIDE a transaction (after BEGIN)
--          W1 ecommerce=!#  the transaction hit an error and must be rolled back
-- ===========================================================================
\if :{?win}
\else
  \set win 1
\endif
\pset pager off
\set ON_ERROR_STOP off
\set VERBOSITY verbose
\set PROMPT1 'W%:win: %/%R%x%# '
\set PROMPT2 'W%:win: %/%R%x%# '

SELECT customer_id AS shopper1 FROM customers WHERE email = 'shopper1@demo.test' \gset
SELECT customer_id AS shopper2 FROM customers WHERE email = 'shopper2@demo.test' \gset
SELECT product_id AS p_case    FROM products WHERE name = 'DEMO Phone Case'  \gset
SELECT product_id AS p_charger FROM products WHERE name = 'DEMO Charger'     \gset
SELECT product_id AS p_last    FROM products WHERE name = 'DEMO Last Item'    \gset
SELECT product_id AS p_price   FROM products WHERE name = 'DEMO Price Check'  \gset
SELECT product_id AS p_promo_a FROM products WHERE name = 'DEMO Promo A'      \gset
SELECT product_id AS p_promo_b FROM products WHERE name = 'DEMO Promo B'      \gset
\echo 'Window' :win 'is ready. shopper1 =' :shopper1 ', shopper2 =' :shopper2
