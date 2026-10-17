-- ===========================================================================
-- NaijaMart constraint tests, Portfolio 1
-- Run AFTER schema.sql:  psql -U postgres -d ecommerce -f constraint_tests.sql
--
-- What it does
--   1. Loads a small set of GOOD rows (this proves valid data is accepted).
--   2. Tries one BAD statement per rule. Each must be rejected, and rejected by
--      the constraint named in the test. If a bad statement is allowed, or a
--      different constraint catches it, that test prints FAIL.
--   3. Prints a results table and a PASS/FAIL count.
--   4. Ends with ROLLBACK, so the database is left exactly as it was.
--
-- Each bad statement runs in its own sub-transaction (an EXCEPTION block), so
-- one failure does not stop the next test.
-- ===========================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP TABLE test_results (
    test_no  INTEGER PRIMARY KEY,
    outcome  TEXT NOT NULL,
    label    TEXT NOT NULL,
    detail   TEXT
);

-- Runs one statement that is EXPECTED to fail with the named constraint.
CREATE FUNCTION pg_temp.expect_fail(p_no INTEGER, p_label TEXT, p_stmt TEXT, p_expected TEXT)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
    v_got  TEXT;
    v_msg  TEXT;
BEGIN
    BEGIN
        EXECUTE p_stmt;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_got = CONSTRAINT_NAME, v_msg = MESSAGE_TEXT;
        IF v_got = p_expected THEN
            INSERT INTO test_results VALUES (p_no, 'PASS', p_label, 'blocked by ' || v_got);
        ELSE
            INSERT INTO test_results VALUES (p_no, 'FAIL', p_label,
                'expected ' || p_expected || ' but got ' || COALESCE(v_got, '(none)') || ': ' || v_msg);
        END IF;
        RETURN;
    END;
    INSERT INTO test_results VALUES (p_no, 'FAIL', p_label, 'statement was ALLOWED');
END
$f$;

DO $do$
DECLARE
    v_cust INTEGER; v_addr INTEGER;
    v_s_lagos INTEGER; v_s_ibadan INTEGER; v_s_kano INTEGER;
    v_cat_phones INTEGER; v_cat_food INTEGER; v_cat_fashion INTEGER;
    v_p_tecno INTEGER; v_p_rice INTEGER; v_p_fabric INTEGER;
    v_rider INTEGER;
    v_o1 INTEGER; v_o2 INTEGER;
    v_o2_del_lagos INTEGER;
BEGIN
    -- ---------------- GOOD DATA (must all be accepted) ----------------
    INSERT INTO customers (full_name, email, phone, wallet_balance)
        VALUES ('Amaka Obi', 'amaka@mail.com', '+2348012345678', 5000)
        RETURNING customer_id INTO v_cust;
    INSERT INTO addresses (customer_id, street, landmark, city, state, is_default)
        VALUES (v_cust, '12 Gwarinpa Road', 'Near the filling station', 'Abuja', 'FCT', true)
        RETURNING address_id INTO v_addr;

    INSERT INTO sellers (business_name, owner_name, email, phone, city, state, bank_name, bank_account_no, status)
        VALUES ('Lagos Gadgets', 'Tunde Bello', 'tunde@lagosgadgets.ng', '+2348022222222', 'Lagos', 'Lagos', 'GTBank', '0123456789', 'APPROVED')
        RETURNING seller_id INTO v_s_lagos;
    INSERT INTO sellers (business_name, owner_name, email, phone, city, state, status)
        VALUES ('Ibadan Grains', 'Funke Adeyemi', 'funke@ibadangrains.ng', '+2348033333333', 'Ibadan', 'Oyo', 'APPROVED')
        RETURNING seller_id INTO v_s_ibadan;
    INSERT INTO sellers (business_name, owner_name, email, phone, city, state, status)
        VALUES ('Kano Fabrics', 'Musa Danjuma', 'musa@kanofabrics.ng', '+2348044444444', 'Kano', 'Kano', 'APPROVED')
        RETURNING seller_id INTO v_s_kano;

    INSERT INTO categories (name, commission_rate) VALUES ('Phones', 0.0700) RETURNING category_id INTO v_cat_phones;
    INSERT INTO categories (name, commission_rate) VALUES ('Groceries', 0.0700) RETURNING category_id INTO v_cat_food;
    INSERT INTO categories (name, commission_rate) VALUES ('Fashion', 0.1000) RETURNING category_id INTO v_cat_fashion;

    INSERT INTO products (seller_id, category_id, name, price, stock_quantity)
        VALUES (v_s_lagos, v_cat_phones, 'Tecno Spark', 85000, 5) RETURNING product_id INTO v_p_tecno;
    INSERT INTO products (seller_id, category_id, name, price, stock_quantity)
        VALUES (v_s_ibadan, v_cat_food, 'Ofada Rice 5kg', 12000, 10) RETURNING product_id INTO v_p_rice;
    INSERT INTO products (seller_id, category_id, name, price, stock_quantity)
        VALUES (v_s_kano, v_cat_fashion, 'Ankara Fabric', 9000, 20) RETURNING product_id INTO v_p_fabric;

    INSERT INTO riders (full_name, phone, courier_company, state)
        VALUES ('Ibrahim Sule', '+2348055555555', 'QuickDrop', 'FCT') RETURNING rider_id INTO v_rider;

    -- Order 1: Amaka's phone plus rice, two sellers, two deliveries, paid by card
    INSERT INTO orders (customer_id, address_id, status, total_amount)
        VALUES (v_cust, v_addr, 'PAID', 97000) RETURNING order_id INTO v_o1;
    INSERT INTO deliveries (order_id, seller_id) VALUES (v_o1, v_s_lagos);
    INSERT INTO deliveries (order_id, seller_id) VALUES (v_o1, v_s_ibadan);
    INSERT INTO order_items (order_id, seller_id, product_id, quantity, unit_price, commission_rate)
        VALUES (v_o1, v_s_lagos, v_p_tecno, 1, 85000, 0.0700);
    INSERT INTO order_items (order_id, seller_id, product_id, quantity, unit_price, commission_rate)
        VALUES (v_o1, v_s_ibadan, v_p_rice, 1, 12000, 0.0700);
    INSERT INTO payments (order_id, method, amount, status, reference, paid_at)
        VALUES (v_o1, 'CARD', 97000, 'SUCCESS', 'PAY-0001', now());
    INSERT INTO wallet_transactions (customer_id, type, amount, reason, reference)
        VALUES (v_cust, 'CREDIT', 5000, 'TOPUP', 'WTX-0001');

    -- Order 2: used as a second order for the cross-order tests (deliveries for Lagos and Ibadan only)
    INSERT INTO orders (customer_id, address_id, total_amount) VALUES (v_cust, v_addr, 5000) RETURNING order_id INTO v_o2;
    INSERT INTO deliveries (order_id, seller_id) VALUES (v_o2, v_s_lagos) RETURNING delivery_id INTO v_o2_del_lagos;
    INSERT INTO deliveries (order_id, seller_id) VALUES (v_o2, v_s_ibadan);

    -- A Pay on Delivery payment tied to its own delivery is valid
    INSERT INTO payments (order_id, delivery_id, method, amount)
        VALUES (v_o2, v_o2_del_lagos, 'POD', 5000);

    INSERT INTO test_results VALUES (0, 'PASS', 'Good data loaded (3 sellers, 3 products, 2 orders, 4 deliveries, 2 items, 2 payments)', 'all valid rows accepted');

    -- ---------------- BAD DATA: earlier tables ----------------
    PERFORM pg_temp.expect_fail(1, 'Customer wallet balance below zero',
        $q$INSERT INTO customers (full_name, email, phone, wallet_balance) VALUES ('Test', 'neg@mail.com', '+2348099990001', -1)$q$,
        'ck_customers_wallet_balance_not_negative');
    PERFORM pg_temp.expect_fail(2, 'Email with capital letters',
        $q$INSERT INTO customers (full_name, email, phone) VALUES ('Test', 'Amaka2@Mail.com', '+2348099990002')$q$,
        'ck_customers_email_format');
    PERFORM pg_temp.expect_fail(3, 'Address in a state that does not exist',
        format($q$INSERT INTO addresses (customer_id, street, city, state) VALUES (%s, '1 Test St', 'Nowhere', 'Atlantis')$q$, v_cust),
        'ck_ng_state_valid');
    PERFORM pg_temp.expect_fail(4, 'Second default address for the same customer',
        format($q$INSERT INTO addresses (customer_id, street, city, state, is_default) VALUES (%s, '2 Test St', 'Abuja', 'FCT', true)$q$, v_cust),
        'uq_addresses_one_default_per_customer');
    PERFORM pg_temp.expect_fail(5, 'Bank account number that is not 10 digits',
        $q$INSERT INTO sellers (business_name, owner_name, email, phone, city, state, bank_name, bank_account_no) VALUES ('X', 'Y', 'x1@shop.ng', '+2348011111111', 'Lagos', 'Lagos', 'GTBank', '12345')$q$,
        'ck_sellers_account_is_nuban');
    PERFORM pg_temp.expect_fail(6, 'Bank name given without an account number',
        $q$INSERT INTO sellers (business_name, owner_name, email, phone, city, state, bank_name) VALUES ('X', 'Y', 'x2@shop.ng', '+2348011111112', 'Lagos', 'Lagos', 'GTBank')$q$,
        'ck_sellers_bank_details_together');
    PERFORM pg_temp.expect_fail(7, 'Category that is its own parent',
        $q$INSERT INTO categories (category_id, parent_category_id, name, commission_rate) OVERRIDING SYSTEM VALUE VALUES (9999, 9999, 'Loop', 0.07)$q$,
        'ck_categories_not_its_own_parent');
    PERFORM pg_temp.expect_fail(8, 'Commission rate above 1 (100 percent)',
        $q$INSERT INTO categories (name, commission_rate) VALUES ('Bad Rate', 1.5)$q$,
        'ck_categories_commission_rate_range');

    -- ---------------- BAD DATA: products and riders ----------------
    PERFORM pg_temp.expect_fail(9, 'Stock going negative',
        format($q$INSERT INTO products (seller_id, category_id, name, price, stock_quantity) VALUES (%s, %s, 'Bad Stock', 1000, -1)$q$, v_s_lagos, v_cat_phones),
        'ck_products_stock_not_negative');
    PERFORM pg_temp.expect_fail(10, 'Product with price zero',
        format($q$INSERT INTO products (seller_id, category_id, name, price) VALUES (%s, %s, 'Free Phone', 0)$q$, v_s_lagos, v_cat_phones),
        'ck_products_price_positive');
    PERFORM pg_temp.expect_fail(11, 'Product for a seller that does not exist',
        format($q$INSERT INTO products (seller_id, category_id, name, price) VALUES (999999, %s, 'Ghost', 1000)$q$, v_cat_phones),
        'fk_products_seller');
    PERFORM pg_temp.expect_fail(12, 'Rider phone in the wrong format',
        $q$INSERT INTO riders (full_name, phone) VALUES ('Bad Phone', '0801')$q$,
        'ck_riders_phone_format');
    PERFORM pg_temp.expect_fail(13, 'Two riders with the same phone',
        $q$INSERT INTO riders (full_name, phone) VALUES ('Copy', '+2348055555555')$q$,
        'uq_riders_phone');

    -- ---------------- BAD DATA: orders ----------------
    PERFORM pg_temp.expect_fail(14, 'Order with a negative total',
        format($q$INSERT INTO orders (customer_id, address_id, total_amount) VALUES (%s, %s, -1)$q$, v_cust, v_addr),
        'ck_orders_total_not_negative');
    PERFORM pg_temp.expect_fail(15, 'Order with an invalid status',
        format($q$INSERT INTO orders (customer_id, address_id, status, total_amount) VALUES (%s, %s, 'LOST', 100)$q$, v_cust, v_addr),
        'ck_orders_status_valid');
    PERFORM pg_temp.expect_fail(16, 'Order for a customer that does not exist',
        format($q$INSERT INTO orders (customer_id, address_id, total_amount) VALUES (999999, %s, 100)$q$, v_addr),
        'fk_orders_customer');
    PERFORM pg_temp.expect_fail(17, 'Deleting an address that an order was sent to',
        format($q$DELETE FROM addresses WHERE address_id = %s$q$, v_addr),
        'fk_orders_address');

    -- ---------------- BAD DATA: deliveries (all use order 2 and the Kano seller) ----------------
    PERFORM pg_temp.expect_fail(18, 'Second delivery for the same seller in the same order',
        format($q$INSERT INTO deliveries (order_id, seller_id) VALUES (%s, %s)$q$, v_o1, v_s_lagos),
        'uq_deliveries_order_seller');
    PERFORM pg_temp.expect_fail(19, 'delivered_time before pickup_time',
        format($q$INSERT INTO deliveries (order_id, seller_id, rider_id, status, pickup_time, delivered_time) VALUES (%s, %s, %s, 'DELIVERED', now(), now() - interval '1 hour')$q$, v_o2, v_s_kano, v_rider),
        'ck_deliveries_delivered_after_pickup');
    PERFORM pg_temp.expect_fail(20, 'PENDING delivery that already has a pickup time',
        format($q$INSERT INTO deliveries (order_id, seller_id, status, pickup_time) VALUES (%s, %s, 'PENDING', now())$q$, v_o2, v_s_kano),
        'ck_deliveries_pending_means_not_picked_up');
    PERFORM pg_temp.expect_fail(21, 'Delivery picked up with no rider',
        format($q$INSERT INTO deliveries (order_id, seller_id, status, pickup_time) VALUES (%s, %s, 'PICKED_UP', now())$q$, v_o2, v_s_kano),
        'ck_deliveries_rider_once_started');
    PERFORM pg_temp.expect_fail(22, 'Delivery status that is not in the list',
        format($q$INSERT INTO deliveries (order_id, seller_id, rider_id, status, pickup_time) VALUES (%s, %s, %s, 'LOST', now())$q$, v_o2, v_s_kano, v_rider),
        'ck_deliveries_status_valid');
    PERFORM pg_temp.expect_fail(23, 'FAILED delivery with zero attempts',
        format($q$INSERT INTO deliveries (order_id, seller_id, rider_id, status, pickup_time, attempt_count) VALUES (%s, %s, %s, 'FAILED', now(), 0)$q$, v_o2, v_s_kano, v_rider),
        'ck_deliveries_failed_has_attempt');
    PERFORM pg_temp.expect_fail(24, 'delivered_time set on a delivery that is not DELIVERED',
        format($q$INSERT INTO deliveries (order_id, seller_id, rider_id, status, pickup_time, delivered_time) VALUES (%s, %s, %s, 'PICKED_UP', now() - interval '1 hour', now())$q$, v_o2, v_s_kano, v_rider),
        'ck_deliveries_delivered_time_matches_status');

    -- ---------------- BAD DATA: order_items ----------------
    -- The key test: the Tecno phone belongs to the Lagos seller. Order 2 HAS a delivery for the
    -- Ibadan seller, so the delivery key is satisfied, and only the product/seller key can object.
    PERFORM pg_temp.expect_fail(25, 'Order item whose seller does not match the product seller',
        format($q$INSERT INTO order_items (order_id, seller_id, product_id, quantity, unit_price, commission_rate) VALUES (%s, %s, %s, 1, 85000, 0.07)$q$, v_o2, v_s_ibadan, v_p_tecno),
        'fk_order_items_product_seller');
    -- Kano really owns the fabric, but order 2 has no Kano delivery, so only the delivery key objects.
    PERFORM pg_temp.expect_fail(26, 'Order item for a seller with no delivery in that order',
        format($q$INSERT INTO order_items (order_id, seller_id, product_id, quantity, unit_price, commission_rate) VALUES (%s, %s, %s, 1, 9000, 0.10)$q$, v_o2, v_s_kano, v_p_fabric),
        'fk_order_items_delivery');
    PERFORM pg_temp.expect_fail(27, 'Order item with quantity zero',
        format($q$INSERT INTO order_items (order_id, seller_id, product_id, quantity, unit_price, commission_rate) VALUES (%s, %s, %s, 0, 85000, 0.07)$q$, v_o2, v_s_lagos, v_p_tecno),
        'ck_order_items_quantity_positive');
    PERFORM pg_temp.expect_fail(28, 'Order item with unit price zero',
        format($q$INSERT INTO order_items (order_id, seller_id, product_id, quantity, unit_price, commission_rate) VALUES (%s, %s, %s, 1, 0, 0.07)$q$, v_o2, v_s_lagos, v_p_tecno),
        'ck_order_items_unit_price_positive');
    PERFORM pg_temp.expect_fail(29, 'Order item with commission rate above 1',
        format($q$INSERT INTO order_items (order_id, seller_id, product_id, quantity, unit_price, commission_rate) VALUES (%s, %s, %s, 1, 85000, 1.5)$q$, v_o2, v_s_lagos, v_p_tecno),
        'ck_order_items_commission_rate_range');
    PERFORM pg_temp.expect_fail(30, 'Same product listed twice in one order',
        format($q$INSERT INTO order_items (order_id, seller_id, product_id, quantity, unit_price, commission_rate) VALUES (%s, %s, %s, 1, 85000, 0.07)$q$, v_o1, v_s_lagos, v_p_tecno),
        'uq_order_items_order_product');

    -- ---------------- BAD DATA: payments ----------------
    PERFORM pg_temp.expect_fail(31, 'Payment with amount zero',
        format($q$INSERT INTO payments (order_id, method, amount, status, reference, paid_at) VALUES (%s, 'CARD', 0, 'SUCCESS', 'PAY-T1', now())$q$, v_o1),
        'ck_payments_amount_positive');
    PERFORM pg_temp.expect_fail(32, 'Pay on Delivery with no delivery named',
        format($q$INSERT INTO payments (order_id, method, amount) VALUES (%s, 'POD', 5000)$q$, v_o1),
        'ck_payments_pod_matches_delivery');
    PERFORM pg_temp.expect_fail(33, 'Online payment that names a delivery',
        format($q$INSERT INTO payments (order_id, delivery_id, method, amount, reference) VALUES (%s, %s, 'CARD', 5000, 'PAY-T2')$q$, v_o2, v_o2_del_lagos),
        'ck_payments_pod_matches_delivery');
    PERFORM pg_temp.expect_fail(34, 'Pay on Delivery pointing at a delivery from a different order',
        format($q$INSERT INTO payments (order_id, delivery_id, method, amount) VALUES (%s, %s, 'POD', 5000)$q$, v_o1, v_o2_del_lagos),
        'fk_payments_order_delivery');
    PERFORM pg_temp.expect_fail(35, 'Two payments with the same provider reference',
        format($q$INSERT INTO payments (order_id, method, amount, reference) VALUES (%s, 'CARD', 100, 'PAY-0001')$q$, v_o1),
        'uq_payments_reference');
    PERFORM pg_temp.expect_fail(36, 'SUCCESS payment with no paid_at',
        format($q$INSERT INTO payments (order_id, method, amount, status, reference) VALUES (%s, 'CARD', 100, 'SUCCESS', 'PAY-T3')$q$, v_o1),
        'ck_payments_paid_at_matches_status');
    PERFORM pg_temp.expect_fail(37, 'Payment method that is not in the list',
        format($q$INSERT INTO payments (order_id, method, amount, reference) VALUES (%s, 'CASH', 100, 'PAY-T4')$q$, v_o1),
        'ck_payments_method_valid');
    PERFORM pg_temp.expect_fail(38, 'Online payment with no provider reference',
        format($q$INSERT INTO payments (order_id, method, amount) VALUES (%s, 'CARD', 100)$q$, v_o1),
        'ck_payments_reference_unless_pod');

    -- ---------------- BAD DATA: wallet_transactions ----------------
    PERFORM pg_temp.expect_fail(39, 'Wallet entry with amount zero',
        format($q$INSERT INTO wallet_transactions (customer_id, type, amount, reason, reference) VALUES (%s, 'CREDIT', 0, 'TOPUP', 'WTX-T1')$q$, v_cust),
        'ck_wallet_txn_amount_positive');
    PERFORM pg_temp.expect_fail(40, 'Two wallet entries with the same reference',
        format($q$INSERT INTO wallet_transactions (customer_id, type, amount, reason, reference) VALUES (%s, 'CREDIT', 100, 'TOPUP', 'WTX-0001')$q$, v_cust),
        'uq_wallet_txn_reference');
    PERFORM pg_temp.expect_fail(41, 'Top up linked to an order',
        format($q$INSERT INTO wallet_transactions (customer_id, order_id, type, amount, reason, reference) VALUES (%s, %s, 'CREDIT', 100, 'TOPUP', 'WTX-T2')$q$, v_cust, v_o1),
        'ck_wallet_txn_order_matches_reason');
    PERFORM pg_temp.expect_fail(42, 'Purchase with no order',
        format($q$INSERT INTO wallet_transactions (customer_id, type, amount, reason, reference) VALUES (%s, 'DEBIT', 100, 'PURCHASE', 'WTX-T3')$q$, v_cust),
        'ck_wallet_txn_order_matches_reason');
    PERFORM pg_temp.expect_fail(43, 'Wallet entry type that is not CREDIT or DEBIT',
        format($q$INSERT INTO wallet_transactions (customer_id, type, amount, reason, reference) VALUES (%s, 'HOLD', 100, 'TOPUP', 'WTX-T4')$q$, v_cust),
        'ck_wallet_txn_type_valid');
    PERFORM pg_temp.expect_fail(44, 'Wallet entry reason that is not in the list',
        format($q$INSERT INTO wallet_transactions (customer_id, order_id, type, amount, reason, reference) VALUES (%s, %s, 'CREDIT', 100, 'GIFT', 'WTX-T5')$q$, v_cust, v_o1),
        'ck_wallet_txn_reason_valid');
END
$do$;

SELECT test_no, outcome, label, detail FROM test_results ORDER BY test_no;

SELECT count(*) FILTER (WHERE outcome = 'PASS') AS passed,
       count(*) FILTER (WHERE outcome = 'FAIL') AS failed,
       count(*)                                 AS total
FROM test_results;

-- Leave the database exactly as it was before the tests.
ROLLBACK;
