-- ===========================================================================
-- NaijaMart schema, Portfolio 1 (complete: all 11 tables)
-- Tables, in creation order: customers, addresses, sellers, categories,
--   products, riders, orders, deliveries, order_items, payments,
--   wallet_transactions
-- Run with: psql -U postgres -d ecommerce -f schema.sql
--
-- Design decisions used in this file
--   1. Primary keys are identity columns (GENERATED ALWAYS), so PostgreSQL
--      hands out the ids and nobody can insert a clashing id by mistake.
--   2. Fixed lists of values (for example sellers.status) use
--      CHECK (column IN (...)) and not CREATE TYPE. A CHECK can be changed with
--      a simple DROP and ADD CONSTRAINT, but a CREATE TYPE enum cannot lose or
--      rename values easily. The lists here (statuses) may still grow, so the
--      CHECK is the safer choice.
--   3. The 37 Nigerian states are the exception: that list is long, shared by
--      several tables and almost never changes, so it is one DOMAIN (ng_state).
--   4. Emails are stored in lowercase (enforced by a CHECK) so a plain UNIQUE
--      constraint also stops Amaka@mail.com and amaka@mail.com being two accounts.
--   5. Money is NUMERIC(12,2), never FLOAT. Financial rows (orders, payments,
--      wallet_transactions, order_items) use ON DELETE RESTRICT so history
--      cannot be erased by deleting a parent row.
--   6. Secondary indexes for speed are NOT created here. They are added in
--      Portfolio 2 so the before and after query plans are a fair comparison.
--      The only indexes below are the ones that enforce a rule.
-- ===========================================================================

\set ON_ERROR_STOP on

BEGIN;

-- Development reset: lets the script be run again from scratch.
-- Exact reverse of the creation order, so every table is dropped before the
-- tables it depends on. No CASCADE is used, so a wrong order would fail loudly.
DROP TABLE IF EXISTS wallet_transactions;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS deliveries;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS riders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS categories;
DROP TABLE IF EXISTS sellers;
DROP TABLE IF EXISTS addresses;
DROP TABLE IF EXISTS customers;
DROP DOMAIN IF EXISTS ng_state;

-- ---------------------------------------------------------------------------
-- Domain: the 36 Nigerian states plus the Federal Capital Territory (FCT)
-- ---------------------------------------------------------------------------
CREATE DOMAIN ng_state AS VARCHAR(50)
    CONSTRAINT ck_ng_state_valid CHECK (VALUE IN (
        'Abia', 'Adamawa', 'Akwa Ibom', 'Anambra', 'Bauchi', 'Bayelsa',
        'Benue', 'Borno', 'Cross River', 'Delta', 'Ebonyi', 'Edo', 'Ekiti',
        'Enugu', 'FCT', 'Gombe', 'Imo', 'Jigawa', 'Kaduna', 'Kano', 'Katsina',
        'Kebbi', 'Kogi', 'Kwara', 'Lagos', 'Nasarawa', 'Niger', 'Ogun', 'Ondo',
        'Osun', 'Oyo', 'Plateau', 'Rivers', 'Sokoto', 'Taraba', 'Yobe',
        'Zamfara'
    ));

-- ---------------------------------------------------------------------------
-- customers
-- wallet_balance is a cached total of the wallet_transactions ledger. It is
-- changed in the same transaction as every ledger row and can never go below 0.
-- ---------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name       VARCHAR(100)  NOT NULL,
    email           VARCHAR(150)  NOT NULL,
    phone           VARCHAR(20)   NOT NULL,
    wallet_balance  NUMERIC(12,2) NOT NULL DEFAULT 0,
    registered_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT uq_customers_email UNIQUE (email),
    CONSTRAINT uq_customers_phone UNIQUE (phone),
    CONSTRAINT ck_customers_full_name_not_blank CHECK (btrim(full_name) <> ''),
    CONSTRAINT ck_customers_email_format CHECK (
        email = lower(email)
        AND email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    ),
    CONSTRAINT ck_customers_phone_format CHECK (phone ~ '^\+?[0-9]{10,15}$'),
    CONSTRAINT ck_customers_wallet_balance_not_negative CHECK (wallet_balance >= 0)
);

-- ---------------------------------------------------------------------------
-- addresses
-- An address means nothing without its customer, so deleting a customer
-- removes their addresses (ON DELETE CASCADE). Later, orders will point at
-- addresses with RESTRICT, so a customer who has orders cannot be deleted.
-- ---------------------------------------------------------------------------
CREATE TABLE addresses (
    address_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id  INTEGER      NOT NULL,
    street       VARCHAR(200) NOT NULL,
    landmark     VARCHAR(150),
    city         VARCHAR(80)  NOT NULL,
    state        ng_state     NOT NULL,
    is_default   BOOLEAN      NOT NULL DEFAULT false,

    CONSTRAINT fk_addresses_customer
        FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
        ON DELETE CASCADE,
    CONSTRAINT ck_addresses_street_not_blank CHECK (btrim(street) <> ''),
    CONSTRAINT ck_addresses_city_not_blank   CHECK (btrim(city) <> '')
);

-- Rule: a customer can have at most one default address.
CREATE UNIQUE INDEX uq_addresses_one_default_per_customer
    ON addresses (customer_id)
    WHERE is_default;

-- ---------------------------------------------------------------------------
-- sellers
-- status starts as PENDING until NaijaMart approves the seller.
-- Bank details are optional at sign up, but name and account number must be
-- given together. Nigerian bank account numbers (NUBAN) have exactly 10 digits.
-- Phone is not unique because one owner can run more than one shop.
-- ---------------------------------------------------------------------------
CREATE TABLE sellers (
    seller_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    business_name    VARCHAR(150) NOT NULL,
    owner_name       VARCHAR(100) NOT NULL,
    email            VARCHAR(150) NOT NULL,
    phone            VARCHAR(20)  NOT NULL,
    city             VARCHAR(80)  NOT NULL,
    state            ng_state     NOT NULL,
    bank_name        VARCHAR(80),
    bank_account_no  VARCHAR(10),
    status           VARCHAR(10)  NOT NULL DEFAULT 'PENDING',
    joined_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT uq_sellers_email UNIQUE (email),
    CONSTRAINT ck_sellers_business_name_not_blank CHECK (btrim(business_name) <> ''),
    CONSTRAINT ck_sellers_owner_name_not_blank    CHECK (btrim(owner_name) <> ''),
    CONSTRAINT ck_sellers_email_format CHECK (
        email = lower(email)
        AND email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    ),
    CONSTRAINT ck_sellers_phone_format CHECK (phone ~ '^\+?[0-9]{10,15}$'),
    CONSTRAINT ck_sellers_status_valid CHECK (status IN ('PENDING', 'APPROVED', 'SUSPENDED')),
    CONSTRAINT ck_sellers_account_is_nuban CHECK (
        bank_account_no IS NULL OR bank_account_no ~ '^[0-9]{10}$'
    ),
    CONSTRAINT ck_sellers_bank_details_together CHECK (
        (bank_name IS NULL) = (bank_account_no IS NULL)
    )
);

-- ---------------------------------------------------------------------------
-- categories
-- parent_category_id points back to this same table, so Phones can sit under
-- Electronics. NULL means a top level category.
-- commission_rate is the CURRENT rate as a fraction (0.0700 means 7 percent).
-- The rate that was actually applied to each sale is copied onto order_items,
-- so changing it here never rewrites old payouts.
-- ---------------------------------------------------------------------------
CREATE TABLE categories (
    category_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent_category_id  INTEGER,
    name                VARCHAR(80)  NOT NULL,
    commission_rate     NUMERIC(5,4) NOT NULL,

    CONSTRAINT uq_categories_name UNIQUE (name),
    CONSTRAINT fk_categories_parent
        FOREIGN KEY (parent_category_id) REFERENCES categories (category_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_categories_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT ck_categories_not_its_own_parent CHECK (
        parent_category_id IS NULL OR parent_category_id <> category_id
    ),
    CONSTRAINT ck_categories_commission_rate_range CHECK (
        commission_rate BETWEEN 0 AND 1
    )
);

-- ---------------------------------------------------------------------------
-- products
-- Each product belongs to exactly one seller (seller_id NOT NULL), so seller
-- details live only in sellers. Stock is a column here because stock follows
-- the seller's own location. Two sellers selling the same phone are two rows.
-- UNIQUE (product_id, seller_id) looks redundant, because product_id is already
-- the primary key. It exists only so order_items can point at the PAIR with a
-- composite foreign key, which proves the item names the product's real seller.
-- ---------------------------------------------------------------------------
CREATE TABLE products (
    product_id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    seller_id       INTEGER       NOT NULL,
    category_id     INTEGER       NOT NULL,
    name            VARCHAR(200)  NOT NULL,
    description     TEXT,
    price           NUMERIC(12,2) NOT NULL,
    stock_quantity  INTEGER       NOT NULL DEFAULT 0,
    is_active       BOOLEAN       NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT uq_products_id_seller UNIQUE (product_id, seller_id),
    CONSTRAINT fk_products_seller
        FOREIGN KEY (seller_id) REFERENCES sellers (seller_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_products_category
        FOREIGN KEY (category_id) REFERENCES categories (category_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_products_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT ck_products_price_positive CHECK (price > 0),
    CONSTRAINT ck_products_stock_not_negative CHECK (stock_quantity >= 0)
);

-- ---------------------------------------------------------------------------
-- riders
-- Delivery riders and partner couriers. Kept small: deliveries need someone to
-- point at, and a rider is not tied to one seller.
-- ---------------------------------------------------------------------------
CREATE TABLE riders (
    rider_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name        VARCHAR(100) NOT NULL,
    phone            VARCHAR(20)  NOT NULL,
    courier_company  VARCHAR(100),
    state            ng_state,

    CONSTRAINT uq_riders_phone UNIQUE (phone),
    CONSTRAINT ck_riders_full_name_not_blank CHECK (btrim(full_name) <> ''),
    CONSTRAINT ck_riders_phone_format CHECK (phone ~ '^\+?[0-9]{10,15}$')
);

-- ---------------------------------------------------------------------------
-- orders
-- total_amount is a derived value kept on purpose (see normalisation notes).
-- It is set in the same transaction that inserts the items.
-- A customer with orders cannot be deleted, and neither can an address that an
-- order was sent to (RESTRICT). Orders are cancelled, never deleted.
-- ---------------------------------------------------------------------------
CREATE TABLE orders (
    order_id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id   INTEGER       NOT NULL,
    address_id    INTEGER       NOT NULL,
    order_date    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    status        VARCHAR(10)   NOT NULL DEFAULT 'PENDING',
    total_amount  NUMERIC(12,2) NOT NULL,

    CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_orders_address
        FOREIGN KEY (address_id) REFERENCES addresses (address_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_orders_status_valid CHECK (
        status IN ('PENDING', 'PAID', 'SHIPPED', 'DELIVERED', 'CANCELLED')
    ),
    CONSTRAINT ck_orders_total_not_negative CHECK (total_amount >= 0)
);

-- ---------------------------------------------------------------------------
-- deliveries
-- One delivery per seller per order, because each seller ships from their own
-- place. Created with the order, BEFORE its items, with status PENDING.
--   PENDING    created with the order, not yet picked up (no rider, no pickup)
--   PICKED_UP  rider has collected the parcel from the seller
--   DELIVERED  handed to the customer
--   FAILED     latest attempt failed (a later attempt can still succeed)
-- Two UNIQUE constraints exist only as targets for composite foreign keys:
--   (order_id, seller_id)   target of order_items
--   (order_id, delivery_id) target of payments
-- ---------------------------------------------------------------------------
CREATE TABLE deliveries (
    delivery_id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id             INTEGER      NOT NULL,
    seller_id            INTEGER      NOT NULL,
    rider_id             INTEGER,
    status               VARCHAR(10)  NOT NULL DEFAULT 'PENDING',
    pickup_time          TIMESTAMPTZ,
    delivered_time       TIMESTAMPTZ,
    attempt_count        INTEGER      NOT NULL DEFAULT 0,
    last_failure_reason  VARCHAR(200),

    CONSTRAINT uq_deliveries_order_seller   UNIQUE (order_id, seller_id),
    CONSTRAINT uq_deliveries_order_delivery UNIQUE (order_id, delivery_id),
    CONSTRAINT fk_deliveries_order
        FOREIGN KEY (order_id) REFERENCES orders (order_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_deliveries_seller
        FOREIGN KEY (seller_id) REFERENCES sellers (seller_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_deliveries_rider
        FOREIGN KEY (rider_id) REFERENCES riders (rider_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_deliveries_status_valid CHECK (
        status IN ('PENDING', 'PICKED_UP', 'DELIVERED', 'FAILED')
    ),
    CONSTRAINT ck_deliveries_attempt_count_not_negative CHECK (attempt_count >= 0),
    -- PENDING if and only if nobody has picked the parcel up yet.
    CONSTRAINT ck_deliveries_pending_means_not_picked_up CHECK (
        (status = 'PENDING') = (pickup_time IS NULL)
    ),
    -- Once the delivery has started, a rider must be on it.
    CONSTRAINT ck_deliveries_rider_once_started CHECK (
        status = 'PENDING' OR rider_id IS NOT NULL
    ),
    -- delivered_time is filled if and only if the status is DELIVERED.
    CONSTRAINT ck_deliveries_delivered_time_matches_status CHECK (
        (status = 'DELIVERED') = (delivered_time IS NOT NULL)
    ),
    CONSTRAINT ck_deliveries_delivered_after_pickup CHECK (
        delivered_time IS NULL OR delivered_time >= pickup_time
    ),
    CONSTRAINT ck_deliveries_failed_has_attempt CHECK (
        status <> 'FAILED' OR attempt_count >= 1
    ),
    CONSTRAINT ck_deliveries_failure_reason_not_blank CHECK (
        last_failure_reason IS NULL OR btrim(last_failure_reason) <> ''
    )
);

-- ---------------------------------------------------------------------------
-- order_items
-- unit_price and commission_rate are frozen copies taken when the item is
-- created (historical snapshots, see normalisation notes).
-- Two composite foreign keys share seller_id, so the item, its product and its
-- delivery must all name the SAME seller:
--   (product_id, seller_id) -> products   the product really belongs to that seller
--   (order_id, seller_id)   -> deliveries that seller has a delivery in this order
-- The second key also guarantees the order exists, so there is no separate
-- order_id foreign key to orders (it would be redundant).
-- One row per product per order: buying 3 of the same phone is quantity = 3.
-- ---------------------------------------------------------------------------
CREATE TABLE order_items (
    order_item_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id         INTEGER       NOT NULL,
    seller_id        INTEGER       NOT NULL,
    product_id       INTEGER       NOT NULL,
    quantity         INTEGER       NOT NULL,
    unit_price       NUMERIC(12,2) NOT NULL,
    commission_rate  NUMERIC(5,4)  NOT NULL,

    CONSTRAINT uq_order_items_order_product UNIQUE (order_id, product_id),
    CONSTRAINT fk_order_items_product_seller
        FOREIGN KEY (product_id, seller_id) REFERENCES products (product_id, seller_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_order_items_delivery
        FOREIGN KEY (order_id, seller_id) REFERENCES deliveries (order_id, seller_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_order_items_quantity_positive   CHECK (quantity > 0),
    CONSTRAINT ck_order_items_unit_price_positive CHECK (unit_price > 0),
    CONSTRAINT ck_order_items_commission_rate_range CHECK (
        commission_rate BETWEEN 0 AND 1
    )
);

-- ---------------------------------------------------------------------------
-- payments
-- Online payments (CARD, TRANSFER, USSD, WALLET) cover the whole order and
-- leave delivery_id empty. Pay on Delivery (POD) is cash paid to a rider, and
-- each rider collects for ONE delivery, so a POD payment names its delivery.
-- The composite key (order_id, delivery_id) stops a payment from pointing at a
-- delivery that belongs to a different order. When delivery_id is NULL the
-- composite key is not checked, which is exactly what online payments need.
-- Card numbers are never stored, only the provider reference.
-- ---------------------------------------------------------------------------
CREATE TABLE payments (
    payment_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id     INTEGER       NOT NULL,
    delivery_id  INTEGER,
    method       VARCHAR(10)   NOT NULL,
    amount       NUMERIC(12,2) NOT NULL,
    status       VARCHAR(10)   NOT NULL DEFAULT 'PENDING',
    reference    VARCHAR(100),
    created_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
    paid_at      TIMESTAMPTZ,

    CONSTRAINT uq_payments_reference UNIQUE (reference),
    CONSTRAINT fk_payments_order
        FOREIGN KEY (order_id) REFERENCES orders (order_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_payments_order_delivery
        FOREIGN KEY (order_id, delivery_id) REFERENCES deliveries (order_id, delivery_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_payments_method_valid CHECK (
        method IN ('CARD', 'TRANSFER', 'USSD', 'POD', 'WALLET')
    ),
    CONSTRAINT ck_payments_status_valid CHECK (
        status IN ('PENDING', 'SUCCESS', 'FAILED', 'REFUNDED')
    ),
    CONSTRAINT ck_payments_amount_positive CHECK (amount > 0),
    -- A delivery link is present if and only if the method is Pay on Delivery.
    CONSTRAINT ck_payments_pod_matches_delivery CHECK (
        (method = 'POD') = (delivery_id IS NOT NULL)
    ),
    -- Every non-POD payment must carry the provider reference.
    CONSTRAINT ck_payments_reference_unless_pod CHECK (
        method = 'POD' OR reference IS NOT NULL
    ),
    CONSTRAINT ck_payments_reference_not_blank CHECK (
        reference IS NULL OR btrim(reference) <> ''
    ),
    -- paid_at is filled if and only if money actually arrived.
    CONSTRAINT ck_payments_paid_at_matches_status CHECK (
        (status IN ('SUCCESS', 'REFUNDED')) = (paid_at IS NOT NULL)
    )
);

-- ---------------------------------------------------------------------------
-- wallet_transactions
-- The ledger and the source of truth for the wallet. amount is always positive;
-- type says whether it adds (CREDIT) or removes (DEBIT) money. Rows are never
-- updated or deleted: a mistake is fixed by a new reversing row.
-- customers.wallet_balance is the cached total, changed in the same transaction.
-- Type and reason are deliberately NOT tied together, because a reversal of a
-- refund is a DEBIT with reason REFUND. A top up has no order, every other
-- reason belongs to an order.
-- ---------------------------------------------------------------------------
CREATE TABLE wallet_transactions (
    wallet_txn_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id    INTEGER       NOT NULL,
    order_id       INTEGER,
    type           VARCHAR(6)    NOT NULL,
    amount         NUMERIC(12,2) NOT NULL,
    reason         VARCHAR(10)   NOT NULL,
    reference      VARCHAR(100)  NOT NULL,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT uq_wallet_txn_reference UNIQUE (reference),
    CONSTRAINT fk_wallet_txn_customer
        FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_wallet_txn_order
        FOREIGN KEY (order_id) REFERENCES orders (order_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_wallet_txn_type_valid   CHECK (type IN ('CREDIT', 'DEBIT')),
    CONSTRAINT ck_wallet_txn_reason_valid CHECK (reason IN ('TOPUP', 'PURCHASE', 'REFUND')),
    CONSTRAINT ck_wallet_txn_amount_positive CHECK (amount > 0),
    CONSTRAINT ck_wallet_txn_reference_not_blank CHECK (btrim(reference) <> ''),
    CONSTRAINT ck_wallet_txn_order_matches_reason CHECK (
        (reason = 'TOPUP') = (order_id IS NULL)
    )
);

COMMIT;
    