-- ===========================================================================
-- NaijaMart seed data, Portfolio 2, part 1 of 2: reference data
-- Fills: categories, sellers, products, customers, addresses, riders
-- Run AFTER schema.sql:  psql -U postgres -d ecommerce -f seed_reference.sql
--
-- Safe to run again: it empties all 11 tables first (see seed-plan.md).
-- Repeatable: setseed(0.42) makes random() give the same sequence each run.
-- Every value is built to pass the schema constraints (phone format, 10 digit
-- account numbers, lowercase emails, valid states, unique phones).
-- ===========================================================================

\set ON_ERROR_STOP on
\timing on

BEGIN;

DO $$ BEGIN PERFORM setseed(0.42); END $$;

-- Step 1: empty everything and restart the id counters (ids will be 1..N).
TRUNCATE TABLE wallet_transactions, payments, order_items, deliveries, orders,
               riders, products, categories, sellers, addresses, customers
    RESTART IDENTITY;

-- ---------------------------------------------------------------------------
-- Helpers (temporary, they vanish when the session ends)
-- ---------------------------------------------------------------------------
-- pick(arr): a random element of a text array
CREATE FUNCTION pg_temp.pick(arr text[]) RETURNS text
LANGUAGE sql VOLATILE AS $$
    SELECT arr[1 + floor(random() * array_length(arr, 1))::int]
$$;

-- rand_int(lo, hi): a random whole number from lo to hi, both included
CREATE FUNCTION pg_temp.rand_int(lo int, hi int) RETURNS int
LANGUAGE sql VOLATILE AS $$
    SELECT lo + floor(random() * (hi - lo + 1))::int
$$;

-- ---------------------------------------------------------------------------
-- Lists of Nigerian names, streets, banks and so on
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE seed_lists AS
SELECT
    ARRAY['Amaka','Chinedu','Ngozi','Emeka','Chioma','Tunde','Bola','Funke','Ibrahim','Aisha',
          'Musa','Fatima','Yusuf','Zainab','Segun','Kemi','Femi','Adaobi','Obinna','Ifeanyi',
          'Blessing','Grace','Tobi','Damilola','Sade','Uche','Nneka','Kelechi','Halima','Abdul',
          'Bashir','Hauwa','Ayodele','Folake','Chukwudi','Ebuka','Titilayo','Gbenga','Rashida',
          'Danjuma','Emmanuel','Ruth','Samuel','Peace','Joy','Daniel']::text[] AS first_names,
    ARRAY['Obi','Okafor','Adeyemi','Bello','Ibrahim','Musa','Okonkwo','Eze','Balogun','Adebayo',
          'Ogunleye','Nwosu','Abubakar','Suleiman','Danjuma','Ojo','Akinola','Chukwu','Umar',
          'Lawal','Afolabi','Okeke','Olawale','Nnamdi','Yakubu','Salami','Onuoha','Adewale',
          'Mohammed','Egwu','Ajayi','Bakare','Igwe','Aliyu','Fashola','Oyewole']::text[] AS last_names,
    ARRAY['gmail.com','yahoo.com','outlook.com','mail.com']::text[] AS domains,
    ARRAY['803','806','810','813','816','703','706','708','802','805','807','815','903','906']::text[] AS phone_prefixes,
    ARRAY['Adeola Odeku Street','Allen Avenue','Awolowo Road','Herbert Macaulay Way','Aminu Kano Crescent',
          'Ahmadu Bello Way','Ikorodu Road','Opebi Road','Admiralty Way','Gwarinpa Avenue',
          'Constitution Road','Port Harcourt Road','Ring Road','Independence Layout','Old Airport Road',
          'Bode Thomas Street','Murtala Mohammed Way','Airport Road','Sapele Road','Ogui Road']::text[] AS streets,
    ARRAY['Near the filling station','Opposite the market','Beside the church','Behind the school',
          'Close to the roundabout','Next to the pharmacy','Near the mosque','Opposite the bank',
          'Beside the supermarket','Near the bus stop']::text[] AS landmarks,
    ARRAY['GTBank','Access Bank','Zenith Bank','First Bank','UBA','Fidelity Bank','Sterling Bank',
          'Wema Bank','Union Bank','Stanbic IBTC']::text[] AS banks,
    ARRAY['Naija','Royal','Prime','Golden','Zenith','Alpha','Unity','Crown','Bright','Swift',
          'Grand','Elite']::text[] AS biz_prefixes,
    ARRAY['Gadgets','Fabrics','Provisions','Beauty Hub','Electronics','Kitchenware','Fashion House',
          'Stores','Traders','Mart','Supplies','Collections']::text[] AS biz_types,
    ARRAY['QuickDrop','SwiftRun Logistics','Trailblaze Couriers','Eagle Dispatch','Kobo Express',
          'Metro Movers']::text[] AS couriers,
    ARRAY['Standard','Premium','Mini','Plus','Pro','Classic','Lite','Max']::text[] AS styles;

-- ---------------------------------------------------------------------------
-- Places: city and state always chosen as a matching pair. Some cities are
-- listed twice so Lagos, Abuja and Port Harcourt appear more often, as in life.
-- Every state is in the ng_state list.
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE seed_places AS
SELECT row_number() OVER (ORDER BY state, city) AS idx, city, state
FROM (VALUES
    ('Ikeja','Lagos'), ('Ikeja','Lagos'), ('Lekki','Lagos'), ('Lekki','Lagos'), ('Yaba','Lagos'),
    ('Surulere','Lagos'), ('Victoria Island','Lagos'), ('Ikorodu','Lagos'), ('Ajah','Lagos'),
    ('Gwarinpa','FCT'), ('Gwarinpa','FCT'), ('Wuse','FCT'), ('Garki','FCT'), ('Maitama','FCT'),
    ('Kubwa','FCT'), ('Lugbe','FCT'),
    ('Port Harcourt','Rivers'), ('Port Harcourt','Rivers'), ('Ibadan','Oyo'), ('Ibadan','Oyo'),
    ('Kano','Kano'), ('Kano','Kano'), ('Kaduna','Kaduna'), ('Zaria','Kaduna'), ('Enugu','Enugu'),
    ('Onitsha','Anambra'), ('Awka','Anambra'), ('Benin City','Edo'), ('Benin City','Edo'),
    ('Abeokuta','Ogun'), ('Sagamu','Ogun'), ('Jos','Plateau'), ('Owerri','Imo'), ('Warri','Delta'),
    ('Asaba','Delta'), ('Uyo','Akwa Ibom'), ('Calabar','Cross River'), ('Ilorin','Kwara'),
    ('Akure','Ondo'), ('Maiduguri','Borno'), ('Sokoto','Sokoto'), ('Aba','Abia'), ('Lokoja','Kogi'),
    ('Minna','Niger'), ('Makurdi','Benue'), ('Osogbo','Osun'), ('Yenagoa','Bayelsa')
) AS v(city, state);

-- ---------------------------------------------------------------------------
-- Product templates: what each sub-category sells, with a naira price range.
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE seed_product_templates AS
SELECT row_number() OVER (ORDER BY leaf, item) AS idx, leaf, item, min_price, max_price
FROM (VALUES
    ('Smartphones','Tecno Spark 10',95000,140000), ('Smartphones','Infinix Hot 30',130000,180000),
    ('Smartphones','Samsung Galaxy A15',170000,230000), ('Smartphones','Redmi 13C',110000,150000),
    ('Smartphones','Refurbished iPhone 11',400000,550000),
    ('Phone Accessories','Phone Case',1500,6000), ('Phone Accessories','Fast Charger 33W',4500,12000),
    ('Phone Accessories','Power Bank 20000mAh',12000,28000), ('Phone Accessories','Wireless Earbuds',8000,35000),
    ('Tablets','Samsung Galaxy Tab A9',180000,260000), ('Tablets','Lenovo Tab M10',150000,210000),
    ('Tablets','Kids Learning Tablet',60000,95000),
    ('Mens Wear','Senator Wear Set',25000,60000), ('Mens Wear','Polo Shirt',6000,15000),
    ('Mens Wear','Jeans Trousers',12000,28000), ('Mens Wear','Agbada Set',45000,120000),
    ('Womens Wear','Ankara Gown',18000,55000), ('Womens Wear','Lace Blouse',9000,25000),
    ('Womens Wear','Wrapper and Blouse Set',15000,40000), ('Womens Wear','Maxi Dress',14000,38000),
    ('Shoes and Bags','Leather Sandals',9000,22000), ('Shoes and Bags','Sneakers',15000,45000),
    ('Shoes and Bags','Ladies Handbag',12000,50000), ('Shoes and Bags','Laptop Backpack',10000,28000),
    ('Ankara and Fabrics','Ankara Fabric 6 Yards',8000,18000), ('Ankara and Fabrics','Aso Oke Fabric',25000,80000),
    ('Ankara and Fabrics','Lace Material 5 Yards',20000,70000),
    ('Rice and Grains','Ofada Rice 5kg',11000,16000), ('Rice and Grains','Long Grain Rice 50kg',68000,95000),
    ('Rice and Grains','Beans 10kg',14000,22000), ('Rice and Grains','Garri 5kg',4500,8000),
    ('Rice and Grains','Semovita 2kg',3000,5500),
    ('Cooking Oil and Seasoning','Groundnut Oil 5 Litres',14000,22000),
    ('Cooking Oil and Seasoning','Palm Oil 4 Litres',12000,20000),
    ('Cooking Oil and Seasoning','Seasoning Cubes Carton',4500,8500),
    ('Cooking Oil and Seasoning','Curry and Thyme Pack',1200,2800),
    ('Drinks and Beverages','Malt Drink Pack of 24',14000,21000),
    ('Drinks and Beverages','Bottled Water Pack of 12',2800,4800),
    ('Drinks and Beverages','Zobo Drink 1 Litre',1500,3200), ('Drinks and Beverages','Instant Coffee 200g',4000,9000),
    ('Snacks','Chin Chin 1kg',4000,8000), ('Snacks','Plantain Chips Pack',1000,2500),
    ('Snacks','Groundnut Snack Pack of 12',3000,6500),
    ('Cookware','Non-stick Pot Set',22000,65000), ('Cookware','Pressure Cooker 6L',30000,70000),
    ('Cookware','Frying Pan 28cm',7000,18000),
    ('Small Appliances','Blender 1.5L',18000,45000), ('Small Appliances','Electric Kettle',9000,22000),
    ('Small Appliances','Microwave Oven 20L',65000,120000), ('Small Appliances','Rice Cooker 1.8L',22000,50000),
    ('Furniture','Office Chair',45000,120000), ('Furniture','Dining Table Set',150000,450000),
    ('Furniture','Bookshelf',35000,90000),
    ('Bedding','Bedsheet Set',9000,28000), ('Bedding','Duvet King Size',18000,55000),
    ('Bedding','Pillow Pair',6000,16000),
    ('Skincare','Shea Butter Pot 500g',4500,9500), ('Skincare','Vitamin C Serum',7000,18000),
    ('Skincare','Sunscreen SPF 50',6000,15000), ('Skincare','Black Soap 500g',2500,6000),
    ('Hair Care','Hair Growth Oil',4500,11000), ('Hair Care','Human Hair Wig 14 inch',60000,220000),
    ('Hair Care','Braiding Hair Pack',2500,6500), ('Hair Care','Hair Dryer',11000,28000),
    ('Fragrance','Body Spray Set',5000,14000), ('Fragrance','Oud Perfume 100ml',18000,60000),
    ('Fragrance','Perfume Oil 30ml',6000,18000),
    ('Makeup','Lipstick Set',6000,16000), ('Makeup','Foundation',8000,22000),
    ('Makeup','Makeup Brush Set',7000,20000)
) AS v(leaf, item, min_price, max_price);

-- ---------------------------------------------------------------------------
-- Step 2: categories. Parents first, then children (self reference).
-- Fashion and Beauty earn 10 percent commission, everything else 7 percent.
-- Children copy their parent's rate.
-- ---------------------------------------------------------------------------
INSERT INTO categories (name, commission_rate) VALUES
    ('Phones', 0.0700), ('Fashion', 0.1000), ('Groceries', 0.0700),
    ('Home and Kitchen', 0.0700), ('Beauty', 0.1000);

INSERT INTO categories (parent_category_id, name, commission_rate)
SELECT p.category_id, v.child, p.commission_rate
FROM (VALUES
    ('Phones','Smartphones'), ('Phones','Phone Accessories'), ('Phones','Tablets'),
    ('Fashion','Mens Wear'), ('Fashion','Womens Wear'), ('Fashion','Shoes and Bags'),
    ('Fashion','Ankara and Fabrics'),
    ('Groceries','Rice and Grains'), ('Groceries','Cooking Oil and Seasoning'),
    ('Groceries','Drinks and Beverages'), ('Groceries','Snacks'),
    ('Home and Kitchen','Cookware'), ('Home and Kitchen','Small Appliances'),
    ('Home and Kitchen','Furniture'), ('Home and Kitchen','Bedding'),
    ('Beauty','Skincare'), ('Beauty','Hair Care'), ('Beauty','Fragrance'), ('Beauty','Makeup')
) AS v(parent, child)
JOIN categories p ON p.name = v.parent
ORDER BY v.parent, v.child;

-- ---------------------------------------------------------------------------
-- Step 3: 500 sellers.
-- Every 20th seller is PENDING, every 25th (not already pending) is SUSPENDED,
-- the rest are APPROVED. 85 percent have bank details, the rest have none.
-- Bank name and account number are both filled or both empty (schema rule).
-- ---------------------------------------------------------------------------
INSERT INTO sellers (business_name, owner_name, email, phone, city, state,
                     bank_name, bank_account_no, status, joined_at)
SELECT s.biz,
       s.fn || ' ' || s.ln,
       lower(s.fn || '.' || s.ln || s.n::text || '@shops.naijamart.ng'),
       '+234' || s.pfx || lpad(s.n::text, 7, '0'),
       pl.city,
       pl.state,
       CASE WHEN s.r_bank < 0.85 THEN s.bank END,
       CASE WHEN s.r_bank < 0.85 THEN lpad(floor(s.r_acct * 10000000000)::bigint::text, 10, '0') END,
       CASE WHEN s.n % 20 = 0 THEN 'PENDING'
            WHEN s.n % 25 = 0 THEN 'SUSPENDED'
            ELSE 'APPROVED' END,
       TIMESTAMPTZ '2026-10-01 00:00:00+00' - (400 + s.r_join * 500) * INTERVAL '1 day'
FROM (
    SELECT g AS n,
           pg_temp.pick(l.first_names)     AS fn,
           pg_temp.pick(l.last_names)      AS ln,
           pg_temp.pick(l.phone_prefixes)  AS pfx,
           pg_temp.pick(l.biz_prefixes) || ' ' || pg_temp.pick(l.biz_types) AS biz,
           pg_temp.pick(l.banks)           AS bank,
           random() AS r_bank,
           random() AS r_acct,
           random() AS r_join,
           pg_temp.rand_int(1, (SELECT count(*)::int FROM seed_places)) AS pidx
    FROM generate_series(1, 500) AS g
    CROSS JOIN seed_lists l
) s
JOIN seed_places pl ON pl.idx = s.pidx
ORDER BY s.n;

-- ---------------------------------------------------------------------------
-- Step 4: 8,000 products.
-- Only APPROVED sellers get products, and the choice is skewed (power 1.5) so
-- some sellers have many products and some few, as on a real marketplace.
-- Only sub-categories are used. About 5 percent are out of stock and 10
-- percent have 1 to 5 left, which is useful for the last item demos later.
-- 20 percent have no description. 95 percent are active.
-- ---------------------------------------------------------------------------
INSERT INTO products (seller_id, category_id, name, description, price,
                      stock_quantity, is_active, created_at)
SELECT x.seller_id,
       c.category_id,
       t.item || ' ' || x.style,
       CASE WHEN x.r_desc < 0.8 THEN 'Quality ' || t.item || ' with nationwide delivery.' END,
       (round((t.min_price + x.r_price * (t.max_price - t.min_price))::numeric / 50) * 50)::numeric(12,2),
       CASE WHEN x.r_stock < 0.05 THEN 0
            WHEN x.r_stock < 0.15 THEN 1 + floor(x.r_stock2 * 5)::int
            ELSE 10 + floor(x.r_stock2 * 490)::int END,
       x.r_active < 0.95,
       s.joined_at + x.r_created * (TIMESTAMPTZ '2026-10-01 00:00:00+00' - s.joined_at)
FROM (
    SELECT g AS n,
           a.aps[1 + floor(array_length(a.aps, 1) * power(random(), 1.5))::int] AS seller_id,
           pg_temp.rand_int(1, (SELECT count(*)::int FROM seed_product_templates)) AS tidx,
           pg_temp.pick(l.styles) AS style,
           random() AS r_desc,
           random() AS r_price,
           random() AS r_stock,
           random() AS r_stock2,
           random() AS r_active,
           random() AS r_created
    FROM generate_series(1, 8000) AS g
    CROSS JOIN seed_lists l
    CROSS JOIN (SELECT array_agg(seller_id ORDER BY seller_id) AS aps
                FROM sellers WHERE status = 'APPROVED') a
) x
JOIN seed_product_templates t ON t.idx = x.tidx
JOIN categories c ON c.name = t.leaf
JOIN sellers s ON s.seller_id = x.seller_id
ORDER BY x.n;

-- ---------------------------------------------------------------------------
-- Step 5: 25,000 customers.
-- The number n is part of every email and phone, so both are always unique.
-- wallet_balance stays 0 until the wallet ledger is seeded in part 2.
-- ---------------------------------------------------------------------------
INSERT INTO customers (full_name, email, phone, wallet_balance, registered_at)
SELECT f.fn || ' ' || f.ln,
       lower(f.fn || '.' || f.ln || f.n::text || '@' || f.dom),
       '+234' || f.pfx || lpad(f.n::text, 7, '0'),
       0,
       TIMESTAMPTZ '2026-10-01 00:00:00+00' - f.r_reg * INTERVAL '730 days'
FROM (
    SELECT g AS n,
           pg_temp.pick(l.first_names)    AS fn,
           pg_temp.pick(l.last_names)     AS ln,
           pg_temp.pick(l.domains)        AS dom,
           pg_temp.pick(l.phone_prefixes) AS pfx,
           random() AS r_reg
    FROM generate_series(1, 25000) AS g
    CROSS JOIN seed_lists l
) f
ORDER BY f.n;

-- ---------------------------------------------------------------------------
-- Step 6: addresses. Everyone gets one default address; about 35 percent also
-- get a second, non-default one. Half of the addresses have a landmark.
-- ---------------------------------------------------------------------------
INSERT INTO addresses (customer_id, street, landmark, city, state, is_default)
SELECT p.customer_id,
       pg_temp.rand_int(1, 150)::text || ' ' || pg_temp.pick(l.streets),
       CASE WHEN random() < 0.5 THEN pg_temp.pick(l.landmarks) END,
       pl.city,
       pl.state,
       true
FROM (
    SELECT customer_id,
           pg_temp.rand_int(1, (SELECT count(*)::int FROM seed_places)) AS pidx
    FROM customers
) p
JOIN seed_places pl ON pl.idx = p.pidx
CROSS JOIN seed_lists l
ORDER BY p.customer_id;

INSERT INTO addresses (customer_id, street, landmark, city, state, is_default)
SELECT p.customer_id,
       pg_temp.rand_int(1, 150)::text || ' ' || pg_temp.pick(l.streets),
       CASE WHEN random() < 0.5 THEN pg_temp.pick(l.landmarks) END,
       pl.city,
       pl.state,
       false
FROM (
    SELECT customer_id,
           pg_temp.rand_int(1, (SELECT count(*)::int FROM seed_places)) AS pidx
    FROM customers
    WHERE random() < 0.35
) p
JOIN seed_places pl ON pl.idx = p.pidx
CROSS JOIN seed_lists l
ORDER BY p.customer_id;

-- ---------------------------------------------------------------------------
-- Step 7: 300 riders. Phones are unique (the number n is part of each one).
-- ---------------------------------------------------------------------------
INSERT INTO riders (full_name, phone, courier_company, state)
SELECT r.fn || ' ' || r.ln,
       '+234' || r.pfx || lpad((3000000 + r.n)::text, 7, '0'),
       r.courier,
       pl.state
FROM (
    SELECT g AS n,
           pg_temp.pick(l.first_names)    AS fn,
           pg_temp.pick(l.last_names)     AS ln,
           pg_temp.pick(l.phone_prefixes) AS pfx,
           pg_temp.pick(l.couriers)       AS courier,
           pg_temp.rand_int(1, (SELECT count(*)::int FROM seed_places)) AS pidx
    FROM generate_series(1, 300) AS g
    CROSS JOIN seed_lists l
) r
JOIN seed_places pl ON pl.idx = r.pidx
ORDER BY r.n;

-- ---------------------------------------------------------------------------
-- Checks: stop with an error (and roll everything back) if anything is off.
-- ---------------------------------------------------------------------------
DO $check$
DECLARE
    n INTEGER;
BEGIN
    SELECT count(*) INTO n FROM categories;
    IF n <> 24 THEN RAISE EXCEPTION 'categories: expected 24, got %', n; END IF;

    SELECT count(*) INTO n FROM sellers;
    IF n <> 500 THEN RAISE EXCEPTION 'sellers: expected 500, got %', n; END IF;

    SELECT count(*) INTO n FROM products;
    IF n <> 8000 THEN RAISE EXCEPTION 'products: expected 8000, got %', n; END IF;

    SELECT count(*) INTO n FROM customers;
    IF n <> 25000 THEN RAISE EXCEPTION 'customers: expected 25000, got %', n; END IF;

    SELECT count(*) INTO n FROM riders;
    IF n <> 300 THEN RAISE EXCEPTION 'riders: expected 300, got %', n; END IF;

    SELECT count(*) INTO n FROM customers c
    WHERE (SELECT count(*) FROM addresses a WHERE a.customer_id = c.customer_id AND a.is_default) <> 1;
    IF n <> 0 THEN RAISE EXCEPTION '% customers do not have exactly one default address', n; END IF;

    SELECT count(*) INTO n FROM products p JOIN sellers s ON s.seller_id = p.seller_id
    WHERE s.status <> 'APPROVED';
    IF n <> 0 THEN RAISE EXCEPTION '% products belong to a seller that is not approved', n; END IF;

    SELECT count(*) INTO n FROM products p
    WHERE EXISTS (SELECT 1 FROM categories c WHERE c.parent_category_id = p.category_id);
    IF n <> 0 THEN RAISE EXCEPTION '% products sit in a parent category instead of a sub-category', n; END IF;
END
$check$;

COMMIT;

-- ---------------------------------------------------------------------------
-- Summary for the screenshot
-- ---------------------------------------------------------------------------
SELECT 'categories' AS table_name, count(*) AS rows FROM categories
UNION ALL SELECT 'sellers',   count(*) FROM sellers
UNION ALL SELECT 'products',  count(*) FROM products
UNION ALL SELECT 'customers', count(*) FROM customers
UNION ALL SELECT 'addresses', count(*) FROM addresses
UNION ALL SELECT 'riders',    count(*) FROM riders;

SELECT status, count(*) AS sellers FROM sellers GROUP BY status ORDER BY status;

SELECT state, count(*) AS customers
FROM addresses WHERE is_default GROUP BY state ORDER BY customers DESC LIMIT 8;

SELECT s.seller_id, count(*) AS products
FROM products p JOIN sellers s ON s.seller_id = p.seller_id
GROUP BY s.seller_id ORDER BY products DESC LIMIT 5;

-- Repeatability fingerprint: run the script twice, the value must be identical.
SELECT md5(string_agg(email, ',' ORDER BY customer_id)) AS customers_fingerprint FROM customers;
