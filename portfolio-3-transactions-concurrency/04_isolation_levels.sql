-- ===========================================================================
-- DEMO 4: ISOLATION LEVELS. How much of other people's work can I see
-- while my transaction is open?
--
-- Plain words: an "isolation level" is a rule about what a transaction is
-- allowed to see when other transactions are changing data at the same time.
--   READ COMMITTED   (PostgreSQL's default): every statement sees the latest
--                    committed data. Two reads in one transaction can differ.
--   REPEATABLE READ: the transaction sees a frozen "snapshot" taken at its
--                    first query. Two reads always agree.
--   SERIALIZABLE:    the strictest. Results must be the same as if the
--                    transactions had run one after another.
--
-- Part A and B: a non-repeatable read and how REPEATABLE READ fixes it.
-- Part C and D: a "write skew" that REPEATABLE READ allows and SERIALIZABLE stops.
--
-- Use TWO windows (see demo 1 for how to start them):
--   psql -U postgres -d ecommerce -v win=1 -L transcripts\demo4_window1.log
--   psql -U postgres -d ecommerce -v win=2 -L transcripts\demo4_window2.log
--   In both:  \i demo_window.sql
-- ===========================================================================

-- ==== PART | PART A: NON-REPEATABLE READ under READ COMMITTED
-- ==== STEP 1 | WINDOW 1 | PART A: reset, then read the price of "DEMO Price Check" inside a transaction
-- NOTE: The price is 1000.00.
SELECT demo_reset_products();
BEGIN;
SELECT price FROM products WHERE product_id = :p_price;

-- ==== STEP 2 | WINDOW 2 | PART A: someone else changes the price (this commits straight away)
UPDATE products SET price = 1200 WHERE product_id = :p_price;

-- ==== STEP 3 | WINDOW 1 | PART A: read the SAME row again, in the SAME transaction
-- NOTE: SCREENSHOT 1: take a screenshot of both reads.
-- NOTE: Expect 1200.00. The same query gave a different answer inside one transaction. That is a "non-repeatable read".
SELECT price FROM products WHERE product_id = :p_price;
COMMIT;

-- ==== PART | PART B: THE SAME SEQUENCE under REPEATABLE READ
-- ==== STEP 4 | WINDOW 1 | PART B: reset, then start a REPEATABLE READ transaction and read the price
-- NOTE: The price is back to 1000.00.
SELECT demo_reset_products();
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT price FROM products WHERE product_id = :p_price;

-- ==== STEP 5 | WINDOW 2 | PART B: someone else changes the price again
UPDATE products SET price = 1200 WHERE product_id = :p_price;

-- ==== STEP 6 | WINDOW 1 | PART B: read the same row again
-- NOTE: SCREENSHOT 2: take a screenshot of both reads.
-- NOTE: Expect 1000.00 again. Window 1 is looking at its snapshot, so the change is invisible to it.
SELECT price FROM products WHERE product_id = :p_price;

-- ==== STEP 7 | WINDOW 1 | PART B: end the transaction, then look again
-- NOTE: After COMMIT the snapshot is gone, so the new price 1200.00 appears.
COMMIT;
SELECT price FROM products WHERE product_id = :p_price;

-- ==== PART | PART C: WRITE SKEW under REPEATABLE READ (the problem)
-- ==== STEP 8 | WINDOW 1 | PART C: the rule is "at least ONE promo product must stay active". Reset and check
-- NOTE: Story: the shop homepage needs at least one active promo. We have 2 promo products, A and B, both active.
-- NOTE: Two staff members each deactivate a DIFFERENT promo. Each checks first that another one is still active.
SELECT demo_reset_products();
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT count(*) AS active_promos FROM products WHERE name LIKE 'DEMO Promo%' AND is_active;

-- ==== STEP 9 | WINDOW 2 | PART C: the second staff member checks too
-- NOTE: Both see 2 active promos, so each thinks "it is safe to deactivate one".
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT count(*) AS active_promos FROM products WHERE name LIKE 'DEMO Promo%' AND is_active;

-- ==== STEP 10 | WINDOW 1 | PART C: staff 1 deactivates Promo A and commits
UPDATE products SET is_active = false WHERE product_id = :p_promo_a;
COMMIT;

-- ==== STEP 11 | WINDOW 2 | PART C: staff 2 deactivates Promo B and commits
-- NOTE: Expect NO error. The two updates touch different rows, so they do not clash.
UPDATE products SET is_active = false WHERE product_id = :p_promo_b;
COMMIT;

-- ==== STEP 12 | WINDOW 1 | PART C, AFTER: the rule is broken
-- NOTE: SCREENSHOT 3: take a screenshot of this result.
-- NOTE: Expect BOTH promos inactive: 0 active. Each staff member checked correctly, but together they broke the rule. That is "write skew".
SELECT name, is_active FROM products WHERE name LIKE 'DEMO Promo%' ORDER BY name;

-- ==== PART | PART D: THE SAME SEQUENCE under SERIALIZABLE (the fix)
-- ==== STEP 13 | WINDOW 1 | PART D: reset, then staff 1 starts a SERIALIZABLE transaction and checks
SELECT demo_reset_products();
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT count(*) AS active_promos FROM products WHERE name LIKE 'DEMO Promo%' AND is_active;

-- ==== STEP 14 | WINDOW 2 | PART D: staff 2 starts a SERIALIZABLE transaction and checks
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT count(*) AS active_promos FROM products WHERE name LIKE 'DEMO Promo%' AND is_active;

-- ==== STEP 15 | WINDOW 1 | PART D: staff 1 deactivates Promo A and commits
-- NOTE: This one succeeds: it is the first to finish.
UPDATE products SET is_active = false WHERE product_id = :p_promo_a;
COMMIT;

-- ==== STEP 16 | WINDOW 2 | PART D: staff 2 deactivates Promo B and tries to commit
-- NOTE: SCREENSHOT 4: take a screenshot showing the error.
-- NOTE: Expect ERROR 40001 "could not serialize access due to read/write dependencies among transactions".
-- NOTE: It may appear on the UPDATE or on the COMMIT; either is fine. PostgreSQL saw that both staff checked, then both changed
-- NOTE: something the other had checked, which could not happen if they had taken turns. So it cancelled the second one.
UPDATE products SET is_active = false WHERE product_id = :p_promo_b;
COMMIT;

-- ==== STEP 17 | WINDOW 2 | PART D: the failed transaction is already over, so RETRY from the start
-- NOTE: (Typing COMMIT on a failed transaction makes PostgreSQL answer ROLLBACK: nothing was saved.)
-- NOTE: On the retry the check sees only 1 active promo, so the app refuses to deactivate the last one.
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT count(*) AS active_promos FROM products WHERE name LIKE 'DEMO Promo%' AND is_active;
ROLLBACK;

-- ==== STEP 18 | WINDOW 1 | PART D, AFTER: the rule still holds
-- NOTE: Expect Promo A inactive, Promo B still active: 1 active promo.
SELECT name, is_active FROM products WHERE name LIKE 'DEMO Promo%' ORDER BY name;
SELECT demo_reset_products();
