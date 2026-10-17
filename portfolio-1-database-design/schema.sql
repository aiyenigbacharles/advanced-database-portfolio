-- ===========================================================================
-- NaijaMart schema, Portfolio 1, part 1 of 3
-- Tables in this file: customers, addresses, sellers, categories
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
--   5. Secondary indexes for speed are NOT created here. They are added in
--      Portfolio 2 so the before and after query plans are a fair comparison.
--      The only indexes below are the ones that enforce a rule.
-- ===========================================================================

\set ON_ERROR_STOP on

BEGIN;

-- Development reset: lets the script be run again from scratch.
-- Order matters because addresses depends on customers.
DROP TABLE IF EXISTS addresses  CASCADE;
DROP TABLE IF EXISTS customers  CASCADE;
DROP TABLE IF EXISTS sellers    CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
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

COMMIT;
