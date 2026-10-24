-- ===========================================================================
-- 00_demo_setup.sql: creates the little bit of test data the demos need.
--   psql -U postgres -d ecommerce -f 00_demo_setup.sql
-- Run it ONCE before the demos. Safe to run again.
--
-- It adds (all clearly marked "demo"/"DEMO", and all removed by 99_cleanup.sql):
--   * 2 demo customers  shopper1@demo.test and shopper2@demo.test
--   * 6 demo products   DEMO Phone Case, DEMO Charger, DEMO Last Item,
--                       DEMO Price Check, DEMO Promo A, DEMO Promo B
--   * helper functions  demo_reset() (and its 3 parts), demo_record_sale(), demo_clear_all()
--   * helper views      demo_oversell_check, demo_wallet_check
-- Your real NaijaMart seed data is not touched.
-- ===========================================================================
\set ON_ERROR_STOP on

-- Two demo customers. The one created first gets the smaller customer_id, which
-- matters in the deadlock demo ("lock the smaller id first").
INSERT INTO customers (full_name, email, phone, wallet_balance)
SELECT v.full_name, v.email, v.phone, 0
FROM (VALUES ('Demo Shopper One', 'shopper1@demo.test', '+2349000000001'),
             ('Demo Shopper Two', 'shopper2@demo.test', '+2349000000002')) AS v(full_name, email, phone)
WHERE NOT EXISTS (SELECT 1 FROM customers c WHERE c.email = v.email);

INSERT INTO addresses (customer_id, street, city, state, is_default)
SELECT c.customer_id, '1 Demo Street', 'Lagos', 'Lagos', true
FROM customers c
WHERE c.email LIKE '%@demo.test'
  AND NOT EXISTS (SELECT 1 FROM addresses a WHERE a.customer_id = c.customer_id);

-- Six demo products, all sold by seller 1 in category 1.
INSERT INTO products (seller_id, category_id, name, price, stock_quantity, is_active)
SELECT 1, 1, v.name, v.price, v.stock, true
FROM (VALUES ('DEMO Phone Case', 3500.00, 10),
             ('DEMO Charger',    6000.00,  2),
             ('DEMO Last Item', 25000.00,  1),
             ('DEMO Price Check', 1000.00, 50),
             ('DEMO Promo A',     500.00,  5),
             ('DEMO Promo B',     500.00,  5)) AS v(name, price, stock)
WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.name = v.name);

-- ---------------------------------------------------------------------------
-- demo_reset(): puts all the demo data back to its starting state.
-- Every demo starts by calling a reset, so every demo can be repeated.
-- It is made of three small parts, so a demo can reset only what it needs:
--   demo_reset_orders()   removes the demo customers' orders
--   demo_reset_wallets()  each demo customer back to 5,000 naira with one ledger row
--   demo_reset_products() demo products back to their starting stock, price, active flag
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION demo_reset_orders() RETURNS text
LANGUAGE plpgsql AS $$
BEGIN
    -- children first, because of the foreign keys
    DELETE FROM payments    WHERE order_id IN (SELECT o.order_id FROM orders o JOIN customers c USING (customer_id) WHERE c.email LIKE '%@demo.test');
    DELETE FROM order_items WHERE order_id IN (SELECT o.order_id FROM orders o JOIN customers c USING (customer_id) WHERE c.email LIKE '%@demo.test');
    DELETE FROM deliveries  WHERE order_id IN (SELECT o.order_id FROM orders o JOIN customers c USING (customer_id) WHERE c.email LIKE '%@demo.test');
    DELETE FROM orders      WHERE customer_id IN (SELECT customer_id FROM customers WHERE email LIKE '%@demo.test');
    RETURN 'demo orders removed';
END
$$;

CREATE OR REPLACE FUNCTION demo_reset_wallets() RETURNS text
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM wallet_transactions WHERE customer_id IN (SELECT customer_id FROM customers WHERE email LIKE '%@demo.test');
    UPDATE customers SET wallet_balance = 5000 WHERE email LIKE '%@demo.test';
    INSERT INTO wallet_transactions (customer_id, type, amount, reason, reference)
    SELECT customer_id, 'CREDIT', 5000, 'TOPUP', 'DEMO-START-' || customer_id
    FROM customers WHERE email LIKE '%@demo.test';
    RETURN 'demo wallets reset';
END
$$;

CREATE OR REPLACE FUNCTION demo_reset_products() RETURNS text
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE products p SET stock_quantity = d.stock, price = d.price, is_active = true
    FROM (VALUES ('DEMO Phone Case', 3500.00, 10), ('DEMO Charger', 6000.00, 2),
                 ('DEMO Last Item', 25000.00, 1), ('DEMO Price Check', 1000.00, 50),
                 ('DEMO Promo A', 500.00, 5), ('DEMO Promo B', 500.00, 5)) AS d(name, price, stock)
    WHERE p.name = d.name;
    RETURN 'demo products reset';
END
$$;

CREATE OR REPLACE FUNCTION demo_reset() RETURNS text
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM demo_reset_orders();
    PERFORM demo_reset_wallets();
    PERFORM demo_reset_products();
    RETURN 'demo data reset';
END
$$;

-- ---------------------------------------------------------------------------
-- demo_record_sale(customer, product, quantity): writes the order rows for one
-- sale (order, delivery, item, total, payment) and returns the new order id.
-- It is the same set of steps you write out by hand in demo 1. It does NOT
-- change the stock; the oversell demo does that itself, because the stock
-- handling is exactly what that demo is about.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION demo_record_sale(p_customer integer, p_product integer, p_qty integer)
RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
    v_order integer;
    v_addr  integer;
    v_seller integer;
BEGIN
    SELECT seller_id INTO v_seller FROM products WHERE product_id = p_product;
    SELECT address_id INTO v_addr FROM addresses WHERE customer_id = p_customer AND is_default;

    INSERT INTO orders (customer_id, address_id, status, total_amount)
    VALUES (p_customer, v_addr, 'PENDING', 0) RETURNING order_id INTO v_order;

    INSERT INTO deliveries (order_id, seller_id) VALUES (v_order, v_seller);

    INSERT INTO order_items (order_id, seller_id, product_id, quantity, unit_price, commission_rate)
    SELECT v_order, p.seller_id, p.product_id, p_qty, p.price, c.commission_rate
    FROM products p JOIN categories c USING (category_id)
    WHERE p.product_id = p_product;

    UPDATE orders SET total_amount = (SELECT SUM(unit_price * quantity) FROM order_items WHERE order_id = v_order)
    WHERE order_id = v_order;

    INSERT INTO payments (order_id, method, amount, status, reference)
    SELECT v_order, 'CARD', total_amount, 'PENDING', 'DEMO-PAY-' || v_order
    FROM orders WHERE order_id = v_order;

    RETURN v_order;
END
$$;

-- Used by the oversell demo: how many "DEMO Last Item" did we sell, and how many
-- were left? The item started with stock 1, so selling 2 means we oversold.
CREATE OR REPLACE VIEW demo_oversell_check AS
SELECT p.name,
       1                          AS stock_at_start,
       p.stock_quantity           AS stock_left,
       COALESCE(SUM(oi.quantity), 0) AS units_sold,
       CASE WHEN COALESCE(SUM(oi.quantity), 0) > 1 THEN 'OVERSOLD' ELSE 'ok' END AS verdict
FROM products p
LEFT JOIN order_items oi ON oi.product_id = p.product_id
WHERE p.name = 'DEMO Last Item'
GROUP BY p.name, p.stock_quantity;

-- Used by the deadlock demo: does each demo customer's wallet_balance equal the
-- total of that customer's wallet_transactions (credits minus debits)?
CREATE OR REPLACE VIEW demo_wallet_check AS
SELECT c.customer_id, c.wallet_balance,
       COALESCE(SUM(CASE w.type WHEN 'CREDIT' THEN w.amount ELSE -w.amount END), 0) AS ledger_total,
       CASE WHEN c.wallet_balance = COALESCE(SUM(CASE w.type WHEN 'CREDIT' THEN w.amount ELSE -w.amount END), 0)
            THEN 'ok' ELSE 'MISMATCH' END AS verdict
FROM customers c
LEFT JOIN wallet_transactions w ON w.customer_id = c.customer_id
WHERE c.email LIKE '%@demo.test'
GROUP BY c.customer_id, c.wallet_balance
ORDER BY c.customer_id;

-- (This one removes the demo data completely; used by 99_cleanup.sql.)
CREATE OR REPLACE FUNCTION demo_clear_all() RETURNS text
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM demo_reset();
    DELETE FROM wallet_transactions WHERE customer_id IN (SELECT customer_id FROM customers WHERE email LIKE '%@demo.test');
    DELETE FROM products WHERE name LIKE 'DEMO %';
    DELETE FROM customers WHERE email LIKE '%@demo.test';   -- their addresses go with them
    RETURN 'demo data removed';
END
$$;

SELECT demo_reset() AS status;
