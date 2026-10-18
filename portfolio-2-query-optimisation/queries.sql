-- ===========================================================================
-- queries.sql: the Portfolio 2 workload (6 queries + 1 optional)
-- Each query is written as a business question.
--
-- The seed data has a fixed "today" (15 October 2026), so these queries use
-- that date instead of now(). That keeps every run, on any day, identical.
--
-- Run one query by pasting it into psql, or the whole file:
--   psql -U postgres -d ecommerce -f queries.sql
-- To measure them, use capture_plans.sql (it runs each query 3 times).
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Q1: Show one customer's last 20 orders, newest first.
-- Customer 10 has 28 orders, so LIMIT 20 really cuts something off.
-- ---------------------------------------------------------------------------
SELECT order_id, order_date, status, total_amount
FROM orders
WHERE customer_id = 10
ORDER BY order_date DESC
LIMIT 20;

-- ---------------------------------------------------------------------------
-- Q2: Find orders that have been PENDING for more than 2 days.
-- A support report: these orders are stuck. Only about 3% of orders are PENDING.
-- ---------------------------------------------------------------------------
SELECT order_id, customer_id, order_date, total_amount
FROM orders
WHERE status = 'PENDING'
  AND order_date < TIMESTAMPTZ '2026-10-15' - INTERVAL '2 days'
ORDER BY order_date;

-- ---------------------------------------------------------------------------
-- Q3: List the items one seller sold in the last 30 days (cancelled orders excluded).
-- A seller dashboard. Seller 33 sold 117 items in that window, which is a typical seller.
-- ---------------------------------------------------------------------------
SELECT o.order_id, o.order_date, p.name AS product, oi.quantity,
       oi.unit_price * oi.quantity AS line_total
FROM order_items oi
JOIN orders   o ON o.order_id   = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE oi.seller_id = 33
  AND o.order_date >= TIMESTAMPTZ '2026-10-15' - INTERVAL '30 days'
  AND o.status <> 'CANCELLED'
ORDER BY o.order_date DESC;

-- ---------------------------------------------------------------------------
-- Q4: Find the top 10 best-selling products in the last 90 days.
-- A marketing report. It has to read about half of all orders.
-- ---------------------------------------------------------------------------
SELECT p.product_id, p.name, SUM(oi.quantity) AS units_sold
FROM order_items oi
JOIN orders   o ON o.order_id   = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_date >= TIMESTAMPTZ '2026-10-15' - INTERVAL '90 days'
  AND o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
GROUP BY p.product_id, p.name
ORDER BY units_sold DESC
LIMIT 10;

-- ---------------------------------------------------------------------------
-- Q5: Calculate the monthly commission earned from each seller.
-- A finance report over every delivered order, so it reads almost everything.
-- ---------------------------------------------------------------------------
SELECT oi.seller_id,
       DATE_TRUNC('month', o.order_date) AS month,
       ROUND(SUM(oi.unit_price * oi.quantity * oi.commission_rate), 2) AS commission
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
WHERE o.status = 'DELIVERED'
GROUP BY oi.seller_id, DATE_TRUNC('month', o.order_date)
ORDER BY oi.seller_id, month;

-- ---------------------------------------------------------------------------
-- Q6: Find the riders with the most FAILED deliveries.
-- Operations report. Only about 1% of deliveries are FAILED.
-- ---------------------------------------------------------------------------
SELECT r.rider_id, r.full_name, COUNT(*) AS failed_deliveries
FROM deliveries d
JOIN riders r ON r.rider_id = d.rider_id
WHERE d.status = 'FAILED'
GROUP BY r.rider_id, r.full_name
ORDER BY failed_deliveries DESC
LIMIT 10;

-- ---------------------------------------------------------------------------
-- Q7: Show one customer's wallet history, newest first.
-- Optional query. Customer 10 has 10 wallet rows out of 26,000.
-- ---------------------------------------------------------------------------
SELECT created_at, type, reason, amount, order_id
FROM wallet_transactions
WHERE customer_id = 10
ORDER BY created_at DESC;
