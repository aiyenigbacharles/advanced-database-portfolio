-- ===========================================================================
-- DEMO 2: ROLLBACK and SAVEPOINT. What happens when one step of an order fails.
--
-- Idea: if something goes wrong half-way, ROLLBACK undoes EVERYTHING since
-- BEGIN, as if the transaction never started. A SAVEPOINT is a bookmark inside
-- the transaction: ROLLBACK TO SAVEPOINT undoes only the work after the
-- bookmark and keeps the rest.
--
-- The failure we cause: Shopper 1 orders 1 phone case (stock 10, fine) and 5
-- chargers (stock only 2). The products table has a CHECK that stock can never
-- go below 0, so taking 5 chargers fails.
--
-- This demo needs only ONE window (Window 1). Start psql as in demo 1:
--   psql -U postgres -d ecommerce -v win=1 -L transcripts\demo2_window1.log
--   then type:  \i demo_window.sql
-- ===========================================================================

-- ==== STEP 1 | WINDOW 1 | Start from a known state
SELECT demo_reset();

-- ==== STEP 2 | WINDOW 1 | PART A, BEFORE: the starting state
-- NOTE: Stock: Phone Case 10, Charger 2. Shopper 1 has no orders.
SELECT name, stock_quantity FROM products WHERE product_id IN (:p_case, :p_charger) ORDER BY name;
SELECT count(*) AS orders_of_shopper1 FROM orders WHERE customer_id = :shopper1;

-- ==== STEP 3 | WINDOW 1 | PART A: start the order; item 1 (1 phone case) works
BEGIN;
INSERT INTO orders (customer_id, address_id, status, total_amount) SELECT :shopper1, address_id, 'PENDING', 0 FROM addresses WHERE customer_id = :shopper1 AND is_default RETURNING order_id \gset
INSERT INTO deliveries (order_id, seller_id) SELECT :order_id, seller_id FROM products WHERE product_id = :p_case;
INSERT INTO order_items (order_id, seller_id, product_id, quantity, unit_price, commission_rate) SELECT :order_id, p.seller_id, p.product_id, 1, p.price, c.commission_rate FROM products p JOIN categories c USING (category_id) WHERE p.product_id = :p_case;
UPDATE products SET stock_quantity = stock_quantity - 1 WHERE product_id = :p_case;

-- ==== STEP 4 | WINDOW 1 | PART A: item 2 (5 chargers) FAILS
-- NOTE: SCREENSHOT 1: take a screenshot showing the error.
-- NOTE: Expect ERROR 23514 "violates check constraint ck_products_stock_not_negative".
-- NOTE: Look at the prompt: the "!" means the whole transaction is now in a failed state.
INSERT INTO order_items (order_id, seller_id, product_id, quantity, unit_price, commission_rate) SELECT :order_id, p.seller_id, p.product_id, 5, p.price, c.commission_rate FROM products p JOIN categories c USING (category_id) WHERE p.product_id = :p_charger;
UPDATE products SET stock_quantity = stock_quantity - 5 WHERE product_id = :p_charger;

-- ==== STEP 5 | WINDOW 1 | PART A: a failed transaction refuses any more work
-- NOTE: Expect ERROR 25P02 "current transaction is aborted, commands ignored until end of transaction block".
SELECT 1;

-- ==== STEP 6 | WINDOW 1 | PART A: ROLLBACK undoes everything
ROLLBACK;

-- ==== STEP 7 | WINDOW 1 | PART A, AFTER: nothing is left behind
-- NOTE: SCREENSHOT 2: take a screenshot of these results.
-- NOTE: Expect 0 orders, 0 order items, and the stock back at 10 and 2. Even the phone case that DID work was undone.
SELECT count(*) AS orders_of_shopper1 FROM orders WHERE customer_id = :shopper1;
SELECT count(*) AS items_for_demo_products FROM order_items WHERE product_id IN (:p_case, :p_charger);
SELECT name, stock_quantity FROM products WHERE product_id IN (:p_case, :p_charger) ORDER BY name;

-- ==== STEP 8 | WINDOW 1 | PART B (SAVEPOINT): the same order again; item 1 works
-- NOTE: This time we put a bookmark (SAVEPOINT) after item 1.
BEGIN;
INSERT INTO orders (customer_id, address_id, status, total_amount) SELECT :shopper1, address_id, 'PENDING', 0 FROM addresses WHERE customer_id = :shopper1 AND is_default RETURNING order_id \gset
INSERT INTO deliveries (order_id, seller_id) SELECT :order_id, seller_id FROM products WHERE product_id = :p_case;
INSERT INTO order_items (order_id, seller_id, product_id, quantity, unit_price, commission_rate) SELECT :order_id, p.seller_id, p.product_id, 1, p.price, c.commission_rate FROM products p JOIN categories c USING (category_id) WHERE p.product_id = :p_case;
UPDATE products SET stock_quantity = stock_quantity - 1 WHERE product_id = :p_case;
SAVEPOINT before_charger;

-- ==== STEP 9 | WINDOW 1 | PART B: item 2 fails again
-- NOTE: Same error as before. The "!" appears in the prompt.
INSERT INTO order_items (order_id, seller_id, product_id, quantity, unit_price, commission_rate) SELECT :order_id, p.seller_id, p.product_id, 5, p.price, c.commission_rate FROM products p JOIN categories c USING (category_id) WHERE p.product_id = :p_charger;
UPDATE products SET stock_quantity = stock_quantity - 5 WHERE product_id = :p_charger;

-- ==== STEP 10 | WINDOW 1 | PART B: go back to the bookmark only
-- NOTE: SCREENSHOT 3: take a screenshot here.
-- NOTE: The prompt goes back to "*": the transaction is alive again. Only the charger item was discarded.
ROLLBACK TO SAVEPOINT before_charger;
SELECT count(*) AS items_in_this_order FROM order_items WHERE order_id = :order_id;

-- ==== STEP 11 | WINDOW 1 | PART B: finish the order with the items that worked, then COMMIT
UPDATE orders SET total_amount = (SELECT SUM(unit_price * quantity) FROM order_items WHERE order_id = :order_id) WHERE order_id = :order_id;
INSERT INTO payments (order_id, method, amount, status, reference) SELECT order_id, 'CARD', total_amount, 'PENDING', 'DEMO-PAY-' || order_id FROM orders WHERE order_id = :order_id;
COMMIT;

-- ==== STEP 12 | WINDOW 1 | PART B, AFTER: the order exists with just the phone case
-- NOTE: SCREENSHOT 4: take a screenshot of these results.
-- NOTE: Expect 1 order with 1 item and total 3,500. Phone Case stock is 9, Charger stock is still 2.
SELECT o.order_id, o.status, o.total_amount, count(i.order_item_id) AS items FROM orders o LEFT JOIN order_items i USING (order_id) WHERE o.customer_id = :shopper1 GROUP BY o.order_id;
SELECT name, stock_quantity FROM products WHERE product_id IN (:p_case, :p_charger) ORDER BY name;
