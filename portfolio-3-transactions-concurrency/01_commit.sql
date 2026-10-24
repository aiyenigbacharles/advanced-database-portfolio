-- ===========================================================================
-- DEMO 1: COMMIT. "Place an order" as ONE transaction.
--
-- Idea: placing an order changes several tables (orders, deliveries,
-- order_items, products, payments). A TRANSACTION makes them all happen
-- together or not at all. Until you type COMMIT, nobody else can see the work.
--
-- HOW TO USE THIS FILE (do not run it with -f; paste it step by step)
--   Open two PowerShell windows in this folder and start psql in each:
--     Window 1:  psql -U postgres -d ecommerce -v win=1 -L transcripts\demo1_window1.log
--     Window 2:  psql -U postgres -d ecommerce -v win=2 -L transcripts\demo1_window2.log
--   In BOTH windows type:  \i demo_window.sql
--   Then paste each STEP into the window named in its heading, in order.
--   (-L saves everything psql prints to a log file, for your transcript.)
-- ===========================================================================

-- ==== STEP 1 | WINDOW 1 | Start from a known state
-- NOTE: demo_reset() puts the demo data back to its starting state, so you can repeat this demo.
SELECT demo_reset();

-- ==== STEP 2 | WINDOW 1 | BEFORE: what the shop looks like right now
-- NOTE: Phone Case stock is 10, Charger stock is 2, and Shopper 1 has no orders.
SELECT name, stock_quantity FROM products WHERE product_id IN (:p_case, :p_charger) ORDER BY name;
SELECT count(*) AS orders_of_shopper1 FROM orders WHERE customer_id = :shopper1;

-- ==== STEP 3 | WINDOW 1 | Open the transaction and create the order
-- NOTE: Shopper 1 wants 2 phone cases and 1 charger.
-- NOTE: BEGIN starts the transaction. The "*" in the prompt shows we are inside one.
-- NOTE: \gset keeps the new order's id in a variable called order_id.
BEGIN;
INSERT INTO orders (customer_id, address_id, status, total_amount) SELECT :shopper1, address_id, 'PENDING', 0 FROM addresses WHERE customer_id = :shopper1 AND is_default RETURNING order_id \gset
SELECT :order_id AS new_order_id;

-- ==== STEP 4 | WINDOW 1 | Add the delivery, the two items, and take the stock
-- NOTE: Each item needs its delivery to exist first (the schema ties items to a delivery).
INSERT INTO deliveries (order_id, seller_id) SELECT :order_id, seller_id FROM products WHERE product_id = :p_case;
INSERT INTO order_items (order_id, seller_id, product_id, quantity, unit_price, commission_rate) SELECT :order_id, p.seller_id, p.product_id, 2, p.price, c.commission_rate FROM products p JOIN categories c USING (category_id) WHERE p.product_id = :p_case;
INSERT INTO order_items (order_id, seller_id, product_id, quantity, unit_price, commission_rate) SELECT :order_id, p.seller_id, p.product_id, 1, p.price, c.commission_rate FROM products p JOIN categories c USING (category_id) WHERE p.product_id = :p_charger;
UPDATE products SET stock_quantity = stock_quantity - 2 WHERE product_id = :p_case;
UPDATE products SET stock_quantity = stock_quantity - 1 WHERE product_id = :p_charger;

-- ==== STEP 5 | WINDOW 1 | Work out the total and record the payment
UPDATE orders SET total_amount = (SELECT SUM(unit_price * quantity) FROM order_items WHERE order_id = :order_id) WHERE order_id = :order_id;
INSERT INTO payments (order_id, method, amount, status, reference) SELECT order_id, 'CARD', total_amount, 'PENDING', 'DEMO-PAY-' || order_id FROM orders WHERE order_id = :order_id;

-- ==== STEP 6 | WINDOW 1 | Window 1 can see its own, not-yet-committed work
-- NOTE: The order has 2 items, the total is 13,000 (2 x 3,500 + 1 x 6,000), and stock is already down.
SELECT o.order_id, o.status, o.total_amount, count(i.order_item_id) AS items FROM orders o LEFT JOIN order_items i USING (order_id) WHERE o.order_id = :order_id GROUP BY o.order_id;
SELECT name, stock_quantity FROM products WHERE product_id IN (:p_case, :p_charger) ORDER BY name;

-- ==== STEP 7 | WINDOW 2 | BEFORE COMMIT: Window 2 looks at the same data
-- NOTE: SCREENSHOT 1: take a screenshot of both windows here.
-- NOTE: Expect NOTHING: 0 orders, 0 payments, stock unchanged (10 and 2). The order exists only inside Window 1's transaction.
SELECT count(*) AS orders_of_shopper1 FROM orders WHERE customer_id = :shopper1;
SELECT count(*) AS demo_payments FROM payments WHERE reference LIKE 'DEMO-PAY-%';
SELECT name, stock_quantity FROM products WHERE product_id IN (:p_case, :p_charger) ORDER BY name;

-- ==== STEP 8 | WINDOW 1 | COMMIT: make it permanent
COMMIT;

-- ==== STEP 9 | WINDOW 2 | AFTER COMMIT: the same three queries in Window 2
-- NOTE: SCREENSHOT 2: take a screenshot of both windows here.
-- NOTE: Now everything appears at once: 1 order, 1 payment, and the stock is 8 and 1.
SELECT count(*) AS orders_of_shopper1 FROM orders WHERE customer_id = :shopper1;
SELECT count(*) AS demo_payments FROM payments WHERE reference LIKE 'DEMO-PAY-%';
SELECT name, stock_quantity FROM products WHERE product_id IN (:p_case, :p_charger) ORDER BY name;
SELECT o.order_id, o.status, o.total_amount, count(i.order_item_id) AS items FROM orders o LEFT JOIN order_items i USING (order_id) WHERE o.customer_id = :shopper1 GROUP BY o.order_id;
