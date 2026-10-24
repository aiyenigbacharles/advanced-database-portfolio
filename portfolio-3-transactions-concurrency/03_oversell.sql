-- ===========================================================================
-- DEMO 3: THE LAST-ITEM OVERSELL (the known gap in the design)
--
-- The problem: only 1 "DEMO Last Item" is left (stock = 1) and TWO shoppers
-- try to buy it at the same moment. The CHECK (stock >= 0) cannot save us if
-- the application works out the new stock itself. We show the bug first, then
-- three fixes.
--
-- Plain words:
--   * "read then write": the app reads the stock, decides "1 is enough", and
--     later writes a new number. In between, the other shopper does the same.
--   * A LOCK makes the second person wait until the first has finished.
--
-- Use TWO windows (see demo 1 for how to start them):
--   psql -U postgres -d ecommerce -v win=1 -L transcripts\demo3_window1.log
--   psql -U postgres -d ecommerce -v win=2 -L transcripts\demo3_window2.log
--   In both:  \i demo_window.sql
-- When a step says WAITS, that window will seem to hang. That is the point:
-- it is waiting for the other window. Go to the other window and carry on.
-- demo_record_sale() writes the order rows for one sale (see 00_demo_setup.sql).
-- ===========================================================================

-- ==== PART | PART A: THE BUG (read, then write) under READ COMMITTED (PostgreSQL's default)

-- ==== STEP 1 | WINDOW 1 | PART A: reset, and look at the BEFORE state
-- NOTE: stock_left = 1, units_sold = 0, verdict ok.
SELECT demo_reset();
SELECT * FROM demo_oversell_check;

-- ==== STEP 2 | WINDOW 1 | PART A: shopper 1 starts and READS the stock
BEGIN;
SELECT stock_quantity FROM products WHERE product_id = :p_last;

-- ==== STEP 3 | WINDOW 2 | PART A: shopper 2 starts and READS the stock too
-- NOTE: Both windows now believe there is 1 item left.
BEGIN;
SELECT stock_quantity FROM products WHERE product_id = :p_last;

-- ==== STEP 4 | WINDOW 1 | PART A: shopper 1 buys it
-- NOTE: The app worked out "1 - 1 = 0" and writes the number 0 into the stock, then records the sale.
UPDATE products SET stock_quantity = 0 WHERE product_id = :p_last;
SELECT demo_record_sale(:shopper1, :p_last, 1);
COMMIT;

-- ==== STEP 5 | WINDOW 2 | PART A: shopper 2 ALSO buys it
-- NOTE: Window 2 still believes the stock is 1 (it read that earlier). Nothing stops it.
-- NOTE: Expect NO error. The CHECK does not help, because 0 is a valid stock number.
UPDATE products SET stock_quantity = 0 WHERE product_id = :p_last;
SELECT demo_record_sale(:shopper2, :p_last, 1);
COMMIT;

-- ==== STEP 6 | WINDOW 1 | PART A, AFTER: we sold 2 items but only had 1
-- NOTE: SCREENSHOT 1: take a screenshot of this result.
-- NOTE: Expect units_sold = 2, stock_left = 0, verdict OVERSOLD. One customer will never get their item.
SELECT * FROM demo_oversell_check;

-- ==== PART | PART B: FIX 1, SELECT ... FOR UPDATE (lock the row while you decide)

-- ==== STEP 7 | WINDOW 1 | FIX 1: reset, then shopper 1 reads the stock AND locks the row
-- NOTE: FOR UPDATE means "I am going to change this row, nobody else touch it until I finish."
SELECT demo_reset();
SELECT * FROM demo_oversell_check;
BEGIN;
SELECT stock_quantity FROM products WHERE product_id = :p_last FOR UPDATE;

-- ==== STEP 8 | WINDOW 2 | WAITS | FIX 1: shopper 2 tries to read-and-lock the same row
-- NOTE: Window 2 HANGS. The row is locked by Window 1. This is the fix working.
BEGIN;
SELECT stock_quantity FROM products WHERE product_id = :p_last FOR UPDATE;

-- ==== STEP 9 | WINDOW 1 | FIX 1: shopper 1 buys the item and commits
UPDATE products SET stock_quantity = stock_quantity - 1 WHERE product_id = :p_last;
SELECT demo_record_sale(:shopper1, :p_last, 1);
COMMIT;

-- ==== STEP 10 | WINDOW 2 | RESULT | FIX 1: Window 2 wakes up
-- NOTE: Window 2 now sees stock_quantity = 0, so the app knows the item is sold out.

-- ==== STEP 11 | WINDOW 2 | FIX 1: shopper 2 is told "sold out" and the transaction ends
ROLLBACK;

-- ==== STEP 12 | WINDOW 1 | FIX 1, AFTER
-- NOTE: SCREENSHOT 2: take a screenshot of this result.
-- NOTE: Expect units_sold = 1, stock_left = 0, verdict ok.
SELECT * FROM demo_oversell_check;

-- ==== PART | PART C: FIX 2, one atomic UPDATE ... WHERE stock >= quantity

-- ==== STEP 13 | WINDOW 1 | FIX 2: reset, then shopper 1 does check-and-take in ONE statement
-- NOTE: "Take 1 from the stock, but only if there is at least 1." UPDATE 1 means it worked.
SELECT demo_reset();
SELECT * FROM demo_oversell_check;
BEGIN;
UPDATE products SET stock_quantity = stock_quantity - 1 WHERE product_id = :p_last AND stock_quantity >= 1;

-- ==== STEP 14 | WINDOW 2 | WAITS | FIX 2: shopper 2 runs the same statement
-- NOTE: Window 2 HANGS, waiting for Window 1 to finish with that row.
BEGIN;
UPDATE products SET stock_quantity = stock_quantity - 1 WHERE product_id = :p_last AND stock_quantity >= 1;

-- ==== STEP 15 | WINDOW 1 | FIX 2: shopper 1 records the sale and commits
SELECT demo_record_sale(:shopper1, :p_last, 1);
COMMIT;

-- ==== STEP 16 | WINDOW 2 | RESULT | FIX 2: Window 2 wakes up
-- NOTE: Expect UPDATE 0. PostgreSQL re-checked "stock >= 1" against the new stock (0), so no row matched.
-- NOTE: UPDATE 0 is the app's signal: "sold out". No order is created.

-- ==== STEP 17 | WINDOW 2 | FIX 2: end shopper 2's transaction
ROLLBACK;

-- ==== STEP 18 | WINDOW 1 | FIX 2, AFTER
-- NOTE: SCREENSHOT 3: take a screenshot of this result.
-- NOTE: Expect units_sold = 1, stock_left = 0, verdict ok.
SELECT * FROM demo_oversell_check;

-- ==== PART | PART D: FIX 3, SERIALIZABLE with a retry on error 40001

-- ==== STEP 19 | WINDOW 1 | FIX 3: reset; shopper 1 starts a SERIALIZABLE transaction and reads the stock
-- NOTE: SERIALIZABLE is the strictest level: PostgreSQL makes the result the same as if people took turns.
-- NOTE: The cost: if two transactions clash, PostgreSQL cancels one with error 40001 and the app must try again.
SELECT demo_reset();
SELECT * FROM demo_oversell_check;
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT stock_quantity FROM products WHERE product_id = :p_last;

-- ==== STEP 20 | WINDOW 2 | FIX 3: shopper 2 starts a SERIALIZABLE transaction and reads the stock
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT stock_quantity FROM products WHERE product_id = :p_last;

-- ==== STEP 21 | WINDOW 1 | FIX 3: shopper 1 buys it (same read-then-write code as the bug) and commits
UPDATE products SET stock_quantity = 0 WHERE product_id = :p_last;
SELECT demo_record_sale(:shopper1, :p_last, 1);
COMMIT;

-- ==== STEP 22 | WINDOW 2 | FIX 3: shopper 2 tries to buy it too
-- NOTE: SCREENSHOT 4: take a screenshot showing the error.
-- NOTE: Expect ERROR 40001 "could not serialize access due to concurrent update" on the UPDATE. (The exact wording can vary slightly; the code 40001 is what matters.)
-- NOTE: 40001 means: "this clashed with another transaction; nothing was saved; please try again."
-- NOTE: Any later statement shows ERROR 25P02 (aborted) until you type ROLLBACK.
UPDATE products SET stock_quantity = 0 WHERE product_id = :p_last;
SELECT demo_record_sale(:shopper2, :p_last, 1);

-- ==== STEP 23 | WINDOW 2 | FIX 3: roll back, then RETRY the whole transaction from the start
-- NOTE: A retry is just "do it all again". This time Window 2 reads stock 0, so the app says "sold out".
ROLLBACK;
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT stock_quantity FROM products WHERE product_id = :p_last;
ROLLBACK;

-- ==== STEP 24 | WINDOW 1 | FIX 3, AFTER
-- NOTE: Expect units_sold = 1, stock_left = 0, verdict ok.
SELECT * FROM demo_oversell_check;
