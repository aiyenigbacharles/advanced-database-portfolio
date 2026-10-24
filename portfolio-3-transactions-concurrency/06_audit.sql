-- ===========================================================================
-- DEMO 6: THE CLOSING AUDIT. Did all those transactions keep the data consistent?
--
-- These are the two audit queries from Portfolio 1 (normalization.md). They list
-- a row ONLY when something is wrong, so "(0 rows)" means everything agrees:
--   Audit 1: every order's total_amount equals the sum of its items.
--   Audit 2: every customer's wallet_balance equals credits minus debits.
-- Run them BEFORE the demos (a baseline) and AFTER the demos (the proof).
-- Run it in either window (or with psql -f 06_audit.sql).
-- ===========================================================================
\pset pager off

-- Audit 1: orders.total_amount versus the recalculated sum of its items
SELECT o.order_id, o.total_amount,
       COALESCE(SUM(oi.unit_price * oi.quantity), 0) AS recalculated
FROM orders o
LEFT JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY o.order_id, o.total_amount
HAVING o.total_amount <> COALESCE(SUM(oi.unit_price * oi.quantity), 0);

-- Audit 2: customers.wallet_balance versus the ledger
SELECT c.customer_id, c.wallet_balance,
       COALESCE(SUM(CASE WHEN w.type = 'CREDIT' THEN w.amount ELSE -w.amount END), 0) AS ledger_balance
FROM customers c
LEFT JOIN wallet_transactions w ON w.customer_id = c.customer_id
GROUP BY c.customer_id, c.wallet_balance
HAVING c.wallet_balance <> COALESCE(SUM(CASE WHEN w.type = 'CREDIT' THEN w.amount ELSE -w.amount END), 0);

-- How much data did these audits cover? (for the screenshot: the audits looked at
-- every order and every customer, including the demo ones)
SELECT (SELECT count(*) FROM orders)                                             AS orders_checked,
       (SELECT count(*) FROM customers)                                          AS customers_checked,
       (SELECT count(*) FROM orders o JOIN customers c USING (customer_id)
         WHERE c.email LIKE '%@demo.test')                                       AS demo_orders_included,
       (SELECT count(*) FROM wallet_transactions w JOIN customers c USING (customer_id)
         WHERE c.email LIKE '%@demo.test')                                       AS demo_ledger_rows_included;

-- Bonus check: every demo order's payment equals the order total
SELECT o.order_id, o.total_amount, p.amount
FROM orders o JOIN payments p ON p.order_id = o.order_id
WHERE p.reference LIKE 'DEMO-PAY-%' AND p.amount <> o.total_amount;
