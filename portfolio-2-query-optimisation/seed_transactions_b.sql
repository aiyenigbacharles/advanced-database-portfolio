-- ===========================================================================
-- NaijaMart seed data, Portfolio 2, part 2B of 2B: payments, wallet, verification
-- Covers steps 13 to 16 of seed-plan.md:
--   13 payments      14 wallet ledger + cached balances
--   15 ANALYZE       16 verification
--
-- Run AFTER schema.sql, seed_reference.sql and seed_transactions.sql (part A):
--   psql -U postgres -d ecommerce -f seed_transactions_b.sql
--
-- This is a NEW session, so everything temporary from part A (seed_clock,
-- stg_orders, the helper functions) is gone. This script rebuilds what it needs:
--   * the same fixed "today" (2026-10-15) and setseed(0.42)
--   * everything else is READ from the real tables (orders, deliveries, items)
--
-- Safe to run again: it empties payments and wallet_transactions first and
-- resets every wallet_balance to 0. Part A does not need to be run again.
-- Repeatable: same seed, same fixed "today", same row order, so the same data
-- comes out each time (see the fingerprints at the end).
-- ===========================================================================

\set ON_ERROR_STOP on
\timing on

BEGIN;

DO $$ BEGIN PERFORM setseed(0.42); END $$;

-- Part A must have run first, otherwise there is nothing to pay for.
DO $check$
BEGIN
    IF (SELECT count(*) FROM orders) = 0 OR (SELECT count(*) FROM order_items) = 0 THEN
        RAISE EXCEPTION 'orders or order_items are empty: run seed_transactions.sql (part A) first';
    END IF;
END
$check$;

-- Clean up old payment and wallet data. Nothing points at these two tables,
-- so no CASCADE is needed.
TRUNCATE TABLE payments, wallet_transactions RESTART IDENTITY;
UPDATE customers SET wallet_balance = 0 WHERE wallet_balance <> 0;

-- The same fixed "today" as part A. Nothing in the seed happens after it.
CREATE TEMP TABLE seed_clock AS SELECT TIMESTAMPTZ '2026-10-15 00:00:00+00' AS as_of;

-- ---------------------------------------------------------------------------
-- Step 13: payments
-- First every order's payment is PLANNED in pay_plan (method and status),
-- then the rows are inserted.
--
-- Method mix (share of orders): CARD 40, TRANSFER 28, USSD 10, WALLET 12,
-- POD (Pay on Delivery) 10. POD never goes with a PAID order, because POD
-- orders skip PAID (cash is only collected at delivery), so those are CARD.
--
-- Status, from the order status (the table in seed-plan.md):
--   order PENDING    online: 70% PENDING, 30% FAILED        POD: PENDING
--   order PAID       online: SUCCESS                        (no POD)
--   order SHIPPED    online: SUCCESS                        POD: PENDING
--   order DELIVERED  SUCCESS (POD cash is collected at delivery)
--   order CANCELLED  online: 60% REFUNDED (it had been paid), 40% FAILED
--                    POD: FAILED (cash was never collected)
--
-- Shape:
--   online (CARD, TRANSFER, USSD, WALLET): ONE payment for the whole order,
--       amount = orders.total_amount, delivery_id empty.
--   POD: ONE payment for EACH delivery of the order, amount = the sum of
--       unit_price * quantity of the items in that delivery. So a POD order's
--       payments add up to the order total, and the payment count ends a bit
--       above 100,000 (a 3-seller POD order has 3 payments).
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE pay_plan AS
SELECT y.order_id, y.customer_id, y.order_date, y.order_status, y.total_amount, y.method,
       CASE
           WHEN y.method = 'POD' THEN
               CASE y.order_status WHEN 'DELIVERED' THEN 'SUCCESS'
                                   WHEN 'CANCELLED' THEN 'FAILED'
                                   ELSE 'PENDING' END
           ELSE
               CASE y.order_status WHEN 'PENDING'   THEN CASE WHEN y.r_state < 0.70 THEN 'PENDING' ELSE 'FAILED' END
                                   WHEN 'CANCELLED' THEN CASE WHEN y.r_state < 0.60 THEN 'REFUNDED' ELSE 'FAILED' END
                                   ELSE 'SUCCESS' END
       END AS status,
       -- the payment is started within 5 minutes of the order, never after "today"
       LEAST(y.order_date + y.r_created * 300 * INTERVAL '1 second', y.as_of) AS created_at,
       y.r_paid, y.as_of
FROM (
    SELECT x.order_id, x.customer_id, x.order_date, x.order_status, x.total_amount,
           x.r_state, x.r_created, x.r_paid, k.as_of,
           CASE WHEN x.r_method < 0.40 THEN 'CARD'
                WHEN x.r_method < 0.68 THEN 'TRANSFER'
                WHEN x.r_method < 0.78 THEN 'USSD'
                WHEN x.r_method < 0.90 THEN 'WALLET'
                WHEN x.order_status = 'PAID' THEN 'CARD'
                ELSE 'POD' END AS method
    FROM (
        -- ORDER BY fixes the order the random numbers are handed out in
        SELECT o.order_id, o.customer_id, o.order_date, o.status AS order_status, o.total_amount,
               random() AS r_method, random() AS r_state, random() AS r_created, random() AS r_paid
        FROM orders o
        ORDER BY o.order_id
    ) x
    CROSS JOIN seed_clock k
) y;
ALTER TABLE pay_plan ADD PRIMARY KEY (order_id);
ANALYZE pay_plan;

INSERT INTO payments (order_id, delivery_id, method, amount, status, reference, created_at, paid_at)
SELECT q.order_id, q.delivery_id, q.method, q.amount, q.status, q.reference, q.created_at, q.paid_at
FROM (
    -- online payments: one per order, for the whole order
    SELECT p.order_id, NULL::integer AS delivery_id, p.method, p.total_amount AS amount, p.status,
           'NM-' || p.method || '-' || lpad(p.order_id::text, 7, '0') AS reference,
           p.created_at,
           CASE WHEN p.status IN ('SUCCESS', 'REFUNDED')
                THEN LEAST(p.created_at + (10 + p.r_paid * 590) * INTERVAL '1 second', p.as_of)
           END AS paid_at
    FROM pay_plan p
    WHERE p.method <> 'POD'

    UNION ALL

    -- Pay on Delivery: one payment per delivery, for that delivery's items only.
    -- No provider reference (cash), and paid_at is the moment the rider delivered.
    SELECT p.order_id, d.delivery_id, 'POD', di.amount, p.status, NULL,
           p.created_at,
           CASE WHEN p.status = 'SUCCESS' THEN GREATEST(p.created_at, d.delivered_time) END
    FROM pay_plan p
    JOIN deliveries d ON d.order_id = p.order_id
    JOIN (SELECT order_id, seller_id, sum(unit_price * quantity) AS amount
          FROM order_items
          GROUP BY order_id, seller_id) di
         ON di.order_id = d.order_id AND di.seller_id = d.seller_id
    WHERE p.method = 'POD'
) q
ORDER BY q.order_id, q.delivery_id NULLS FIRST;

-- ---------------------------------------------------------------------------
-- Step 14: wallet ledger, then the cached balance
-- The ledger is the source of truth; customers.wallet_balance is calculated
-- from it afterwards, so the audit query from normalization.md comes back clean.
--
-- Three kinds of event are collected first (wallet_events):
--   DEBIT  a purchase: every WALLET payment that took money (SUCCESS, or
--          REFUNDED later), at the moment it was paid
--   REFUND a CREDIT back to the wallet for every REFUNDED payment (the case
--          study refunds to the wallet), 2 to 72 hours after it was paid
--   TOPUP  a few customers (about 6%) load money without buying anything
-- Then each customer's events are walked in time order with a running balance.
-- A purchase is only written once the balance covers it: if it does not, the
-- customer first tops up (rounded up to a whole 1,000 naira plus a little
-- extra, shortly before the purchase). So the balance is never below 0, not
-- even in the middle of the history. Top-up credits are therefore always
-- at least what the purchases need.
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE wallet_events AS
SELECT pp.customer_id, p.order_id, 'DEBIT'::text AS kind, p.amount, p.paid_at AS event_time
FROM payments p
JOIN pay_plan pp ON pp.order_id = p.order_id
WHERE p.method = 'WALLET' AND p.status IN ('SUCCESS', 'REFUNDED')

UNION ALL

SELECT r.customer_id, r.order_id, 'REFUND', r.amount,
       LEAST(r.paid_at + (2 + r.r_delay * 70) * INTERVAL '1 hour', r.as_of)
FROM (
    SELECT pp.customer_id, p.order_id, p.amount, p.paid_at, k.as_of, random() AS r_delay
    FROM payments p
    JOIN pay_plan pp ON pp.order_id = p.order_id
    CROSS JOIN seed_clock k
    WHERE p.status = 'REFUNDED'
    ORDER BY p.order_id
) r

UNION ALL

SELECT t.customer_id, NULL::integer, 'TOPUP',
       (ARRAY[1000, 2000, 5000, 10000, 20000])[1 + floor(t.r_amount * 5)::int]::numeric,
       t.registered_at + t.r_when * (k.as_of - t.registered_at)
FROM (
    SELECT c.customer_id, c.registered_at,
           random() AS r_pick, random() AS r_amount, random() AS r_when
    FROM customers c
    ORDER BY c.customer_id
) t
CROSS JOIN seed_clock k
WHERE t.r_pick < 0.06;

CREATE TEMP TABLE stg_wallet (
    customer_id integer, order_id integer, type varchar(6), amount numeric(12,2),
    reason varchar(10), reference varchar(100), created_at timestamptz
);

DO $wallet$
DECLARE
    e             RECORD;
    prev_customer INTEGER := 0;
    bal           NUMERIC(14,2) := 0;
    short         NUMERIC(14,2);
    topup         NUMERIC(14,2);
    n_topup       INTEGER := 0;
BEGIN
    FOR e IN
        SELECT w.customer_id, w.order_id, w.kind, w.amount, w.event_time, c.registered_at
        FROM wallet_events w
        JOIN customers c ON c.customer_id = w.customer_id
        ORDER BY w.customer_id, w.event_time, (w.kind = 'DEBIT'), w.order_id NULLS FIRST
    LOOP
        IF e.customer_id <> prev_customer THEN
            prev_customer := e.customer_id;
            bal := 0;
        END IF;

        IF e.kind = 'DEBIT' THEN
            IF bal < e.amount THEN
                -- cannot cover the purchase yet: top up first (1 to 6 hours earlier,
                -- but never before the customer registered)
                short   := e.amount - bal;
                topup   := ceil(short / 1000) * 1000
                           + (ARRAY[0, 0, 1000, 2000, 5000])[1 + floor(random() * 5)::int];
                n_topup := n_topup + 1;
                INSERT INTO stg_wallet VALUES (
                    e.customer_id, NULL, 'CREDIT', topup, 'TOPUP',
                    'WLT-TOP-' || lpad(n_topup::text, 7, '0'),
                    GREATEST(e.event_time - (1 + random() * 5) * INTERVAL '1 hour', e.registered_at));
                bal := bal + topup;
            END IF;
            INSERT INTO stg_wallet VALUES (
                e.customer_id, e.order_id, 'DEBIT', e.amount, 'PURCHASE',
                'WLT-PUR-' || lpad(e.order_id::text, 7, '0'), e.event_time);
            bal := bal - e.amount;

        ELSIF e.kind = 'REFUND' THEN
            INSERT INTO stg_wallet VALUES (
                e.customer_id, e.order_id, 'CREDIT', e.amount, 'REFUND',
                'WLT-REF-' || lpad(e.order_id::text, 7, '0'), e.event_time);
            bal := bal + e.amount;

        ELSE  -- an idle top-up
            n_topup := n_topup + 1;
            INSERT INTO stg_wallet VALUES (
                e.customer_id, NULL, 'CREDIT', e.amount, 'TOPUP',
                'WLT-TOP-' || lpad(n_topup::text, 7, '0'), e.event_time);
            bal := bal + e.amount;
        END IF;
    END LOOP;
END
$wallet$;

INSERT INTO wallet_transactions (customer_id, order_id, type, amount, reason, reference, created_at)
SELECT customer_id, order_id, type, amount, reason, reference, created_at
FROM stg_wallet
ORDER BY created_at, customer_id, reference;

-- The cached balance is the ledger total (credits minus debits).
UPDATE customers c
SET wallet_balance = t.balance
FROM (SELECT customer_id,
             sum(CASE WHEN type = 'CREDIT' THEN amount ELSE -amount END) AS balance
      FROM wallet_transactions
      GROUP BY customer_id) t
WHERE c.customer_id = t.customer_id;

-- ---------------------------------------------------------------------------
-- Step 16a: hard checks. These sit BEFORE the COMMIT, so if any rule is
-- broken the script stops with an error and everything is rolled back.
-- ---------------------------------------------------------------------------
DO $check$
DECLARE
    n      INTEGER;
    v_asof TIMESTAMPTZ := (SELECT as_of FROM seed_clock);
BEGIN
    -- coverage -------------------------------------------------------------
    SELECT count(*) INTO n FROM orders o
    WHERE NOT EXISTS (SELECT 1 FROM payments p WHERE p.order_id = o.order_id);
    IF n <> 0 THEN RAISE EXCEPTION '% orders have no payment', n; END IF;

    SELECT count(*) INTO n FROM (
        SELECT order_id FROM payments GROUP BY order_id
        HAVING (bool_or(method = 'POD') AND bool_or(method <> 'POD'))
            OR count(*) FILTER (WHERE method <> 'POD') > 1) t;
    IF n <> 0 THEN RAISE EXCEPTION '% orders mix online and POD, or have two online payments', n; END IF;

    -- (payments are counted per delivery once, not once per delivery row, so it stays fast)
    SELECT count(*) INTO n
    FROM deliveries d
    LEFT JOIN (SELECT delivery_id, count(*) AS n_pay
               FROM payments WHERE delivery_id IS NOT NULL
               GROUP BY delivery_id) pc ON pc.delivery_id = d.delivery_id
    WHERE d.order_id IN (SELECT order_id FROM payments WHERE method = 'POD')
      AND COALESCE(pc.n_pay, 0) <> 1;
    IF n <> 0 THEN RAISE EXCEPTION '% deliveries of POD orders do not have exactly one payment', n; END IF;

    -- payments must reconcile -------------------------------------------------
    SELECT count(*) INTO n FROM payments p JOIN orders o ON o.order_id = p.order_id
    WHERE p.method <> 'POD' AND p.amount <> o.total_amount;
    IF n <> 0 THEN RAISE EXCEPTION '% online payments differ from their order total', n; END IF;

    SELECT count(*) INTO n
    FROM payments p
    JOIN (SELECT d.delivery_id, sum(i.unit_price * i.quantity) AS amount
          FROM deliveries d
          JOIN order_items i ON i.order_id = d.order_id AND i.seller_id = d.seller_id
          GROUP BY d.delivery_id) di ON di.delivery_id = p.delivery_id
    WHERE p.method = 'POD' AND p.amount <> di.amount;
    IF n <> 0 THEN RAISE EXCEPTION '% POD payments differ from their delivery items', n; END IF;

    SELECT count(*) INTO n FROM (
        SELECT o.order_id FROM orders o JOIN payments p ON p.order_id = o.order_id
        WHERE o.order_id IN (SELECT order_id FROM payments WHERE method = 'POD')
        GROUP BY o.order_id, o.total_amount
        HAVING sum(p.amount) <> o.total_amount) t;
    IF n <> 0 THEN RAISE EXCEPTION '% POD orders whose payments do not add up to the order total', n; END IF;

    -- statuses must agree across tables ------------------------------------------
    SELECT count(*) INTO n FROM payments p JOIN orders o ON o.order_id = p.order_id
    WHERE NOT (
           (o.status = 'PENDING'   AND p.status IN ('PENDING', 'FAILED'))
        OR (o.status IN ('PAID', 'SHIPPED')
            AND ((p.method <> 'POD' AND p.status = 'SUCCESS')
              OR (p.method =  'POD' AND p.status = 'PENDING')))
        OR (o.status = 'DELIVERED' AND p.status = 'SUCCESS')
        OR (o.status = 'CANCELLED' AND (p.status = 'FAILED'
                                        OR (p.status = 'REFUNDED' AND p.method <> 'POD')))
    );
    IF n <> 0 THEN RAISE EXCEPTION '% payments have a status that disagrees with their order', n; END IF;

    SELECT count(*) INTO n FROM payments p JOIN orders o ON o.order_id = p.order_id
    WHERE p.method = 'POD' AND o.status = 'PAID';
    IF n <> 0 THEN RAISE EXCEPTION '% POD payments sit on a PAID order', n; END IF;

    SELECT count(*) INTO n FROM payments p JOIN deliveries d ON d.delivery_id = p.delivery_id
    WHERE p.method = 'POD' AND p.status = 'SUCCESS'
      AND (d.status <> 'DELIVERED' OR p.paid_at < d.delivered_time);
    IF n <> 0 THEN RAISE EXCEPTION '% POD payments were collected before the delivery', n; END IF;

    -- dates ---------------------------------------------------------------------
    SELECT count(*) INTO n FROM payments p JOIN orders o ON o.order_id = p.order_id
    WHERE p.created_at < o.order_date OR p.paid_at < o.order_date;
    IF n <> 0 THEN RAISE EXCEPTION '% payments are dated before their order', n; END IF;

    SELECT count(*) INTO n FROM payments WHERE created_at > v_asof OR paid_at > v_asof;
    IF n <> 0 THEN RAISE EXCEPTION '% payments are dated in the future', n; END IF;

    -- wallet ----------------------------------------------------------------------
    SELECT count(*) INTO n FROM (
        SELECT sum(CASE WHEN type = 'CREDIT' THEN amount ELSE -amount END)
                   OVER (PARTITION BY customer_id
                         ORDER BY created_at, (type = 'DEBIT'), wallet_txn_id) AS running
        FROM wallet_transactions) t
    WHERE running < 0;
    IF n <> 0 THEN RAISE EXCEPTION '% ledger rows leave a wallet below 0', n; END IF;

    SELECT count(*) INTO n FROM (
        SELECT customer_id FROM wallet_transactions GROUP BY customer_id
        HAVING sum(CASE WHEN type = 'CREDIT' THEN amount ELSE 0 END)
             < sum(CASE WHEN type = 'DEBIT'  THEN amount ELSE 0 END)) t;
    IF n <> 0 THEN RAISE EXCEPTION '% customers have more debits than credits', n; END IF;

    SELECT count(*) INTO n FROM payments p
    WHERE p.method = 'WALLET' AND p.status IN ('SUCCESS', 'REFUNDED')
      AND NOT EXISTS (SELECT 1 FROM wallet_transactions w
                      WHERE w.order_id = p.order_id AND w.reason = 'PURCHASE'
                        AND w.type = 'DEBIT' AND w.amount = p.amount);
    IF n <> 0 THEN RAISE EXCEPTION '% wallet payments have no matching ledger debit', n; END IF;

    SELECT count(*) INTO n FROM wallet_transactions w
    WHERE w.reason = 'PURCHASE'
      AND NOT EXISTS (SELECT 1 FROM payments p
                      WHERE p.order_id = w.order_id AND p.method = 'WALLET'
                        AND p.status IN ('SUCCESS', 'REFUNDED') AND p.amount = w.amount);
    IF n <> 0 THEN RAISE EXCEPTION '% ledger purchases have no matching wallet payment', n; END IF;

    SELECT count(*) INTO n FROM payments p
    WHERE p.status = 'REFUNDED'
      AND NOT EXISTS (SELECT 1 FROM wallet_transactions w
                      WHERE w.order_id = p.order_id AND w.reason = 'REFUND'
                        AND w.type = 'CREDIT' AND w.amount = p.amount);
    IF n <> 0 THEN RAISE EXCEPTION '% refunded payments have no matching wallet refund', n; END IF;

    SELECT count(*) INTO n FROM wallet_transactions w
    WHERE w.reason = 'REFUND'
      AND NOT EXISTS (SELECT 1 FROM payments p
                      WHERE p.order_id = w.order_id AND p.status = 'REFUNDED' AND p.amount = w.amount);
    IF n <> 0 THEN RAISE EXCEPTION '% wallet refunds have no matching refunded payment', n; END IF;

    SELECT count(*) INTO n FROM wallet_transactions w JOIN orders o ON o.order_id = w.order_id
    WHERE o.customer_id <> w.customer_id OR w.created_at < o.order_date;
    IF n <> 0 THEN RAISE EXCEPTION '% ledger rows disagree with their order (customer or date)', n; END IF;

    SELECT count(*) INTO n FROM wallet_transactions w JOIN customers c ON c.customer_id = w.customer_id
    WHERE w.created_at < c.registered_at OR w.created_at > v_asof;
    IF n <> 0 THEN RAISE EXCEPTION '% ledger rows are dated before registration or in the future', n; END IF;

    SELECT count(*) INTO n FROM (
        SELECT c.customer_id
        FROM customers c
        LEFT JOIN wallet_transactions w ON w.customer_id = c.customer_id
        GROUP BY c.customer_id, c.wallet_balance
        HAVING c.wallet_balance <> COALESCE(SUM(CASE WHEN w.type = 'CREDIT' THEN w.amount ELSE -w.amount END), 0)) t;
    IF n <> 0 THEN RAISE EXCEPTION '% customers have a wallet_balance that differs from the ledger', n; END IF;
END
$check$;

COMMIT;

-- ---------------------------------------------------------------------------
-- Step 15: fresh statistics for the query planner. After the COMMIT so the new
-- statistics are kept. No speed indexes exist yet, so the Portfolio 2 baseline
-- plans are still a fair "before".
-- ---------------------------------------------------------------------------
ANALYZE customers, addresses, sellers, categories, products, riders,
        orders, deliveries, order_items, payments, wallet_transactions;

-- ---------------------------------------------------------------------------
-- Step 16b: results for the screenshots
-- ---------------------------------------------------------------------------

-- Row counts for all 11 tables
SELECT 'customers' AS table_name, count(*) AS rows FROM customers
UNION ALL SELECT 'addresses',           count(*) FROM addresses
UNION ALL SELECT 'sellers',             count(*) FROM sellers
UNION ALL SELECT 'categories',          count(*) FROM categories
UNION ALL SELECT 'products',            count(*) FROM products
UNION ALL SELECT 'riders',              count(*) FROM riders
UNION ALL SELECT 'orders',              count(*) FROM orders
UNION ALL SELECT 'deliveries',          count(*) FROM deliveries
UNION ALL SELECT 'order_items',         count(*) FROM order_items
UNION ALL SELECT 'payments',            count(*) FROM payments
UNION ALL SELECT 'wallet_transactions', count(*) FROM wallet_transactions;

-- Audit query 1 (normalization.md): orders.total_amount versus the items.
-- It must return ZERO rows.
SELECT o.order_id, o.total_amount,
       COALESCE(SUM(oi.unit_price * oi.quantity), 0) AS recalculated
FROM orders o
LEFT JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY o.order_id, o.total_amount
HAVING o.total_amount <> COALESCE(SUM(oi.unit_price * oi.quantity), 0);

-- Audit query 2 (normalization.md): customers.wallet_balance versus the ledger.
-- It must return ZERO rows.
SELECT c.customer_id, c.wallet_balance,
       COALESCE(SUM(CASE WHEN w.type = 'CREDIT' THEN w.amount ELSE -w.amount END), 0) AS ledger_balance
FROM customers c
LEFT JOIN wallet_transactions w ON w.customer_id = c.customer_id
GROUP BY c.customer_id, c.wallet_balance
HAVING c.wallet_balance <> COALESCE(SUM(CASE WHEN w.type = 'CREDIT' THEN w.amount ELSE -w.amount END), 0);

-- Payments by method and status
SELECT method, status, count(*) AS payments, sum(amount) AS total_naira
FROM payments GROUP BY method, status ORDER BY method, status;

-- Order status against payment status (proves they agree)
SELECT o.status AS order_status, p.method = 'POD' AS pay_on_delivery,
       p.status AS payment_status, count(*) AS payments
FROM orders o JOIN payments p ON p.order_id = o.order_id
GROUP BY o.status, p.method = 'POD', p.status
ORDER BY o.status, pay_on_delivery, p.status;

-- Reconciliation: every number must be 0
SELECT
  (SELECT count(*) FROM payments p JOIN orders o ON o.order_id = p.order_id
    WHERE p.method <> 'POD' AND p.amount <> o.total_amount)            AS online_not_equal_to_order_total,
  (SELECT count(*) FROM (SELECT o.order_id FROM orders o JOIN payments p ON p.order_id = o.order_id
                          WHERE p.method = 'POD'
                          GROUP BY o.order_id, o.total_amount
                          HAVING sum(p.amount) <> o.total_amount) t)   AS pod_orders_not_adding_up,
  (SELECT count(*) FROM payments WHERE status IN ('SUCCESS', 'REFUNDED') AND paid_at IS NULL) AS paid_without_paid_at;

-- Wallet ledger summary
SELECT type, reason, count(*) AS rows, sum(amount) AS total_naira
FROM wallet_transactions GROUP BY type, reason ORDER BY type, reason;

SELECT (SELECT count(DISTINCT customer_id) FROM wallet_transactions) AS customers_with_ledger_rows,
       count(*) FILTER (WHERE wallet_balance > 0)                    AS customers_with_balance,
       min(wallet_balance)                                           AS lowest_balance,
       sum(wallet_balance)                                           AS total_in_wallets
FROM customers;

-- Lowest running balance anywhere in the ledger (must be 0 or more)
SELECT min(running) AS lowest_running_balance
FROM (SELECT sum(CASE WHEN type = 'CREDIT' THEN amount ELSE -amount END)
                 OVER (PARTITION BY customer_id
                       ORDER BY created_at, (type = 'DEBIT'), wallet_txn_id) AS running
      FROM wallet_transactions) t;

-- Fingerprints: run the script twice, these two values must not change
SELECT md5(string_agg(concat_ws('|', order_id, delivery_id, method, amount, status,
                                reference, created_at, paid_at), ',' ORDER BY payment_id)) AS payments_fingerprint
FROM payments;
SELECT md5(string_agg(concat_ws('|', customer_id, order_id, type, amount, reason,
                                reference, created_at), ',' ORDER BY wallet_txn_id)) AS wallet_fingerprint
FROM wallet_transactions;
