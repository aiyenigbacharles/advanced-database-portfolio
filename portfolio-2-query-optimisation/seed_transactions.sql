-- ===========================================================================
-- NaijaMart seed data, Portfolio 2, part 2A of 2B: orders, items, deliveries
-- Covers steps 8 to 12 of seed-plan.md:
--   8  orders            9  staging items       10 deliveries
--   11 order_items       12 orders.total_amount
-- Part B (payments, wallet, verification) comes in the next script.
--
-- Run AFTER schema.sql and seed_reference.sql:
--   psql -U postgres -d ecommerce -f seed_transactions.sql
-- Small trial run (1,000 orders), then scale up:
--   psql -U postgres -d ecommerce -v order_count=1000 -f seed_transactions.sql
--
-- Safe to run again: it empties orders, deliveries, order_items, payments and
-- wallet_transactions first, and resets every wallet_balance to 0.
-- Repeatable: setseed(0.42), and a FIXED "today" instead of now(), so the same
-- data comes out each time.
-- ===========================================================================

\set ON_ERROR_STOP on
\timing on

\if :{?order_count}
\else
\set order_count 100000
\endif

BEGIN;

DO $$ BEGIN PERFORM setseed(0.42); END $$;

-- Clean up old transaction data (CASCADE also clears tables that point at them).
TRUNCATE TABLE orders, deliveries, order_items, payments, wallet_transactions
    RESTART IDENTITY CASCADE;
-- The ledger was just emptied, so the cached balances must go back to 0.
UPDATE customers SET wallet_balance = 0 WHERE wallet_balance <> 0;

-- Helpers (temporary)
CREATE FUNCTION pg_temp.pick(arr text[]) RETURNS text
LANGUAGE sql VOLATILE AS $$
    SELECT arr[1 + floor(random() * array_length(arr, 1))::int]
$$;

CREATE FUNCTION pg_temp.rand_int(lo int, hi int) RETURNS int
LANGUAGE sql VOLATILE AS $$
    SELECT lo + floor(random() * (hi - lo + 1))::int
$$;

-- A fixed "today" for the data. Using now() would give different data each run
-- and could never be reproduced. Nothing in the seed happens after this moment.
CREATE TEMP TABLE seed_clock AS SELECT TIMESTAMPTZ '2026-10-15 00:00:00+00' AS as_of;

-- ---------------------------------------------------------------------------
-- Step 8: plan every order first (stg_orders)
-- The final status is decided NOW, because deliveries and payments are derived
-- from it later.
--
-- Performance: each customer's address ids are collected ONCE into an array.
-- Picking from the array avoids scanning the addresses table once per order.
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE customer_addresses AS
SELECT customer_id, array_agg(address_id ORDER BY address_id) AS addr_ids
FROM addresses
GROUP BY customer_id;
ALTER TABLE customer_addresses ADD PRIMARY KEY (customer_id);
ANALYZE customer_addresses;

-- Status depends on how old the order is, so nothing can be delivered "in the
-- future". Delivery needs up to about 5.6 days after the order, so DELIVERED
-- needs an order at least 7 days old, SHIPPED at least 2 days old.
-- Some old orders stay PENDING on purpose (orders stuck in pending is a report).
CREATE TEMP TABLE stg_orders AS
SELECT d.order_id, d.customer_id, d.address_id, d.order_date, d.order_age_days,
       CASE
           WHEN d.order_age_days < 2 THEN
               CASE WHEN d.r_status < 0.05 THEN 'CANCELLED'
                    WHEN d.r_status < 0.45 THEN 'PENDING'
                    ELSE 'PAID' END
           WHEN d.order_age_days < 7 THEN
               CASE WHEN d.r_status < 0.05 THEN 'CANCELLED'
                    WHEN d.r_status < 0.10 THEN 'PENDING'
                    WHEN d.r_status < 0.25 THEN 'PAID'
                    ELSE 'SHIPPED' END
           WHEN d.order_age_days < 14 THEN
               CASE WHEN d.r_status < 0.04 THEN 'CANCELLED'
                    WHEN d.r_status < 0.07 THEN 'PENDING'
                    WHEN d.r_status < 0.09 THEN 'PAID'
                    WHEN d.r_status < 0.15 THEN 'SHIPPED'
                    ELSE 'DELIVERED' END
           ELSE
               CASE WHEN d.r_status < 0.03  THEN 'CANCELLED'
                    WHEN d.r_status < 0.055 THEN 'PENDING'
                    ELSE 'DELIVERED' END
       END AS status,
       -- 1 to 4 items per order, average 2.5
       CASE WHEN d.r_items < 0.15 THEN 1
            WHEN d.r_items < 0.50 THEN 2
            WHEN d.r_items < 0.85 THEN 3
            ELSE 4 END AS n_items,
       d.r_flow
FROM (
    SELECT e.*,
           extract(epoch FROM (k.as_of - e.order_date)) / 86400.0 AS order_age_days
    FROM (
        SELECT b.order_id, b.customer_id,
               ca.addr_ids[1 + floor(b.r_addr * array_length(ca.addr_ids, 1))::int] AS address_id,
               -- after registration, never after "today"; power 0.5 favours recent dates
               c.registered_at + power(b.r_date, 0.5) * (k2.as_of - c.registered_at) AS order_date,
               b.r_status, b.r_items, b.r_flow
        FROM (
            SELECT g AS order_id,
                   -- some customers order far more often than others
                   1 + floor(cc.n * power(random(), 1.3))::int AS customer_id,
                   random() AS r_date, random() AS r_addr, random() AS r_status,
                   random() AS r_items, random() AS r_flow
            FROM generate_series(1, :order_count) AS g
            CROSS JOIN (SELECT count(*) AS n FROM customers) cc
        ) b
        JOIN customers c ON c.customer_id = b.customer_id
        JOIN customer_addresses ca ON ca.customer_id = b.customer_id
        CROSS JOIN seed_clock k2
    ) e
    CROSS JOIN seed_clock k
) d;
ALTER TABLE stg_orders ADD PRIMARY KEY (order_id);
ANALYZE stg_orders;

-- total_amount is 0 for now; step 12 fills it once the items exist.
INSERT INTO orders (customer_id, address_id, order_date, status, total_amount)
SELECT customer_id, address_id, order_date, status, 0
FROM stg_orders
ORDER BY order_id;

-- The ids must line up with the plan, or later steps would use the wrong orders.
DO $check$
DECLARE n INTEGER;
BEGIN
    SELECT count(*) INTO n FROM orders o
    JOIN stg_orders s ON s.order_id = o.order_id
    WHERE o.customer_id <> s.customer_id OR o.address_id <> s.address_id OR o.status <> s.status;
    IF n <> 0 THEN RAISE EXCEPTION 'orders do not line up with stg_orders (% rows differ)', n; END IF;

    SELECT count(*) INTO n FROM orders o JOIN addresses a ON a.address_id = o.address_id
    WHERE a.customer_id <> o.customer_id;
    IF n <> 0 THEN RAISE EXCEPTION '% orders use an address that belongs to another customer', n; END IF;
END
$check$;

-- ---------------------------------------------------------------------------
-- Step 9: staging items (stg_items)
-- Each order gets 1 to 4 random products. Low product ids are chosen more
-- often (power 2), so some products are best sellers. Picking the same product
-- twice in one order is removed by DISTINCT ON. seller_id and price are copied
-- from the product, commission_rate from the product's category.
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE stg_items AS
SELECT DISTINCT ON (x.order_id, x.product_id)
       x.order_id,
       x.product_id,
       p.seller_id,
       CASE WHEN x.r_qty < 0.75 THEN 1
            WHEN x.r_qty < 0.92 THEN 2
            WHEN x.r_qty < 0.98 THEN 3
            ELSE 4 END AS quantity,
       p.price           AS unit_price,
       c.commission_rate AS commission_rate
FROM (
    SELECT o.order_id, gs.k,
           1 + floor(pc.n * power(random(), 2))::int AS product_id,
           random() AS r_qty
    FROM stg_orders o
    CROSS JOIN LATERAL generate_series(1, o.n_items) AS gs(k)
    CROSS JOIN (SELECT count(*) AS n FROM products) pc
) x
JOIN products   p ON p.product_id  = x.product_id
JOIN categories c ON c.category_id = p.category_id
ORDER BY x.order_id, x.product_id, x.k;
CREATE INDEX stg_items_order_seller ON stg_items (order_id, seller_id);
ANALYZE stg_items;

-- ---------------------------------------------------------------------------
-- Step 10: deliveries, one per distinct (order, seller) pair
-- The delivery status is derived from the ORDER status:
--   PENDING, PAID  all deliveries PENDING (no rider, no pickup time)
--   SHIPPED        the first delivery is PICKED_UP (or FAILED once); the others
--                  are PICKED_UP, PENDING, or DELIVERED (only if the order is
--                  7 days old or more). So a SHIPPED order is never fully delivered.
--   DELIVERED      all deliveries DELIVERED. About 8 percent had a failed
--                  attempt first (attempt_count 1 or 2 and a failure reason).
--   CANCELLED      my choice: 70 percent were cancelled BEFORE pickup, so their
--                  deliveries stay PENDING with no rider. The other 30 percent
--                  (orders at least 3 days old) were attempted and FAILED, then
--                  cancelled: they have a rider, a pickup time and 1 to 3
--                  failed attempts. This gives the returns and refunds reports
--                  something to find. The schema has no "cancelled" delivery
--                  status, so PENDING and FAILED are the two honest options.
-- Times: pickup 3 to 27 hours after the order, delivery 1 to 4 days after pickup
-- (plus 12 hours after a failed attempt). All are before the fixed "today".
-- ---------------------------------------------------------------------------
WITH l1 AS (
    SELECT p.order_id, p.seller_id, p.rn,
           o.status AS order_status, o.order_date, o.order_age_days, o.r_flow,
           random() AS r_mode, random() AS r_pick, random() AS r_transit,
           random() AS r_hist, random() AS r_hist2,
           pg_temp.rand_int(1, (SELECT count(*)::int FROM riders)) AS rider_id,
           pg_temp.pick(ARRAY['Customer did not answer the phone',
                              'Customer not at the address',
                              'Address could not be found',
                              'Customer asked to reschedule',
                              'Rider vehicle breakdown',
                              'Parcel refused at the door']) AS reason
    FROM (
        SELECT q.order_id, q.seller_id,
               row_number() OVER (PARTITION BY q.order_id ORDER BY q.seller_id) AS rn
        FROM (SELECT DISTINCT order_id, seller_id FROM stg_items) q
    ) p
    JOIN stg_orders o ON o.order_id = p.order_id
),
l2 AS (
    SELECT l1.*,
           CASE
               WHEN l1.order_status IN ('PENDING', 'PAID') THEN 'PENDING'
               WHEN l1.order_status = 'DELIVERED' THEN 'DELIVERED'
               WHEN l1.order_status = 'CANCELLED' THEN
                   CASE WHEN l1.r_flow < 0.30 AND l1.order_age_days >= 3 THEN 'FAILED'
                        ELSE 'PENDING' END
               ELSE
                   CASE WHEN l1.rn = 1 THEN
                            CASE WHEN l1.r_mode < 0.80 THEN 'PICKED_UP' ELSE 'FAILED' END
                        WHEN l1.r_mode < 0.55 THEN 'PICKED_UP'
                        WHEN l1.r_mode < 0.80 AND l1.order_age_days >= 7 THEN 'DELIVERED'
                        ELSE 'PENDING' END
           END AS status
    FROM l1
),
l3 AS (
    SELECT l2.*,
           CASE WHEN l2.status = 'FAILED' THEN 1 + floor(l2.r_hist2 * 3)::int
                WHEN l2.status = 'DELIVERED' AND l2.r_hist < 0.08 THEN 1 + (l2.r_hist2 < 0.25)::int
                ELSE 0 END AS attempts,
           l2.order_date + (3 + l2.r_pick * 24) * INTERVAL '1 hour' AS pickup_time
    FROM l2
)
INSERT INTO deliveries (order_id, seller_id, rider_id, status, pickup_time,
                        delivered_time, attempt_count, last_failure_reason)
SELECT l3.order_id,
       l3.seller_id,
       CASE WHEN l3.status = 'PENDING' THEN NULL ELSE l3.rider_id END,
       l3.status,
       CASE WHEN l3.status = 'PENDING' THEN NULL ELSE l3.pickup_time END,
       CASE WHEN l3.status = 'DELIVERED' THEN
            l3.pickup_time + (24 + l3.r_transit * 72
                              + CASE WHEN l3.attempts > 0 THEN 12 ELSE 0 END) * INTERVAL '1 hour'
       END,
       l3.attempts,
       CASE WHEN l3.attempts > 0 THEN l3.reason END
FROM l3
ORDER BY l3.order_id, l3.seller_id;

-- ---------------------------------------------------------------------------
-- Step 11: order items, copied from the staging table.
-- Each delivery already exists, so both composite foreign keys are satisfied.
-- ---------------------------------------------------------------------------
INSERT INTO order_items (order_id, seller_id, product_id, quantity, unit_price, commission_rate)
SELECT order_id, seller_id, product_id, quantity, unit_price, commission_rate
FROM stg_items
ORDER BY order_id, product_id;

-- ---------------------------------------------------------------------------
-- Step 12: order totals, now that the items exist.
-- ---------------------------------------------------------------------------
UPDATE orders o
SET total_amount = t.total
FROM (SELECT order_id, sum(unit_price * quantity) AS total
      FROM order_items
      GROUP BY order_id) t
WHERE o.order_id = t.order_id;

-- ---------------------------------------------------------------------------
-- Checks: stop with an error (and roll everything back) if anything is off.
-- ---------------------------------------------------------------------------
DO $check$
DECLARE
    n      INTEGER;
    v_asof TIMESTAMPTZ := (SELECT as_of FROM seed_clock);
BEGIN
    SELECT count(*) INTO n FROM orders;
    IF n <> (SELECT count(*) FROM stg_orders) THEN RAISE EXCEPTION 'order count is wrong: %', n; END IF;

    SELECT count(*) INTO n FROM orders o
    WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.order_id = o.order_id);
    IF n <> 0 THEN RAISE EXCEPTION '% orders have no items', n; END IF;

    SELECT count(*) INTO n FROM orders o
    WHERE NOT EXISTS (SELECT 1 FROM deliveries d WHERE d.order_id = o.order_id);
    IF n <> 0 THEN RAISE EXCEPTION '% orders have no delivery', n; END IF;

    SELECT count(*) INTO n FROM orders WHERE total_amount <= 0;
    IF n <> 0 THEN RAISE EXCEPTION '% orders have a total of 0 or less', n; END IF;

    SELECT count(*) INTO n FROM orders o JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_date < c.registered_at;
    IF n <> 0 THEN RAISE EXCEPTION '% orders were placed before the customer registered', n; END IF;

    SELECT count(*) INTO n FROM orders WHERE order_date > v_asof;
    IF n <> 0 THEN RAISE EXCEPTION '% orders are dated in the future', n; END IF;

    SELECT count(*) INTO n FROM deliveries
    WHERE pickup_time > v_asof OR delivered_time > v_asof;
    IF n <> 0 THEN RAISE EXCEPTION '% deliveries have a time in the future', n; END IF;

    SELECT count(*) INTO n FROM deliveries d JOIN orders o ON o.order_id = d.order_id
    WHERE d.pickup_time < o.order_date;
    IF n <> 0 THEN RAISE EXCEPTION '% deliveries were picked up before the order', n; END IF;

    -- statuses must agree
    SELECT count(*) INTO n FROM deliveries d JOIN orders o ON o.order_id = d.order_id
    WHERE (o.status = 'DELIVERED' AND d.status <> 'DELIVERED')
       OR (o.status IN ('PENDING', 'PAID') AND d.status <> 'PENDING')
       OR (o.status = 'CANCELLED' AND d.status NOT IN ('PENDING', 'FAILED'));
    IF n <> 0 THEN RAISE EXCEPTION '% deliveries disagree with their order status', n; END IF;

    SELECT count(*) INTO n FROM orders o
    WHERE o.status = 'SHIPPED'
      AND NOT EXISTS (SELECT 1 FROM deliveries d WHERE d.order_id = o.order_id AND d.status <> 'DELIVERED');
    IF n <> 0 THEN RAISE EXCEPTION '% SHIPPED orders have every delivery already delivered', n; END IF;
END
$check$;

COMMIT;

-- ---------------------------------------------------------------------------
-- Results for the screenshot
-- ---------------------------------------------------------------------------
SELECT count(*) FROM orders;        -- 100000
SELECT count(*) FROM order_items;   -- roughly 250000
SELECT count(*) FROM deliveries;

-- Audit query from normalization.md: orders.total_amount versus the items.
-- It must return ZERO rows.
SELECT o.order_id, o.total_amount,
       COALESCE(SUM(oi.unit_price * oi.quantity), 0) AS recalculated
FROM orders o
LEFT JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY o.order_id, o.total_amount
HAVING o.total_amount <> COALESCE(SUM(oi.unit_price * oi.quantity), 0);

-- The status mix
SELECT status, count(*) AS orders,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS percent
FROM orders GROUP BY status ORDER BY orders DESC;

-- Order status against delivery status (proves they agree)
SELECT o.status AS order_status, d.status AS delivery_status, count(*) AS deliveries
FROM orders o JOIN deliveries d ON d.order_id = o.order_id
GROUP BY o.status, d.status ORDER BY o.status, d.status;

-- Items and deliveries per order
SELECT n_items, count(*) AS orders
FROM (SELECT order_id, count(*) AS n_items FROM order_items GROUP BY order_id) t
GROUP BY n_items ORDER BY n_items;
