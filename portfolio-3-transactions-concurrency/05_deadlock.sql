-- ===========================================================================
-- DEMO 5: DEADLOCK. Two sessions each wait for the other. Nobody can move.
--
-- Plain words: a transaction that changes a row LOCKS it until it commits.
-- A deadlock is two people each holding one key and each needing the other's:
--     Window 1 holds Shopper 1's wallet and wants Shopper 2's.
--     Window 2 holds Shopper 2's wallet and wants Shopper 1's.
-- PostgreSQL notices after about 1 second, cancels one transaction with error
-- 40P01, and lets the other continue.
--
-- The story: two "bonus" jobs each add 500 naira of wallet credit to BOTH
-- Shopper 1 and Shopper 2. Each credit = update the balance AND add a ledger
-- row, in the same transaction (so balance and ledger stay in step).
--
-- Use TWO windows (see demo 1 for how to start them):
--   psql -U postgres -d ecommerce -v win=1 -L transcripts\demo5_window1.log
--   psql -U postgres -d ecommerce -v win=2 -L transcripts\demo5_window2.log
--   In both:  \i demo_window.sql
-- Wait about 2 seconds between steps 4 and 5, so the clash is a real one.
-- ===========================================================================

-- ==== PART | PART A: THE DEADLOCK (the two jobs credit the shoppers in OPPOSITE order)
-- ==== STEP 1 | WINDOW 1 | PART A: reset, and look at the BEFORE state
-- NOTE: Both wallets start at 5000, and each equals its ledger total (verdict ok).
SELECT demo_reset_wallets();
SELECT * FROM demo_wallet_check;

-- ==== STEP 2 | WINDOW 1 | PART A: Job 1 starts with Shopper 1 (it now holds Shopper 1's row)
BEGIN;
UPDATE customers SET wallet_balance = wallet_balance + 500 WHERE customer_id = :shopper1;
INSERT INTO wallet_transactions (customer_id, type, amount, reason, reference) VALUES (:shopper1, 'CREDIT', 500, 'TOPUP', 'DEMO-JOB1-S1');

-- ==== STEP 3 | WINDOW 2 | PART A: Job 2 starts with Shopper 2 (it now holds Shopper 2's row)
BEGIN;
UPDATE customers SET wallet_balance = wallet_balance + 500 WHERE customer_id = :shopper2;
INSERT INTO wallet_transactions (customer_id, type, amount, reason, reference) VALUES (:shopper2, 'CREDIT', 500, 'TOPUP', 'DEMO-JOB2-S2');

-- ==== STEP 4 | WINDOW 1 | WAITS | PART A: Job 1 now needs Shopper 2's row. It is held by Window 2, so Window 1 WAITS
-- NOTE: Window 1 hangs. That is normal so far: it is just waiting for Window 2 to finish.
UPDATE customers SET wallet_balance = wallet_balance + 500 WHERE customer_id = :shopper2;

-- ==== STEP 5 | WINDOW 2 | DEADLOCK | PART A: Job 2 now needs Shopper 1's row. It is held by Window 1: a circle
-- NOTE: SCREENSHOT 1: take a screenshot of the error.
-- NOTE: Now each window waits for the other. After about 1 second PostgreSQL steps in.
-- NOTE: Expect ERROR 40P01 "deadlock detected" in THIS window (Window 2). Read the DETAIL lines: they say who waits for whom.
-- NOTE: (PostgreSQL usually cancels the window that started waiting last. If Window 1 got the error instead, swap the window numbers in steps 6 to 9.)
UPDATE customers SET wallet_balance = wallet_balance + 500 WHERE customer_id = :shopper1;

-- ==== STEP 6 | WINDOW 2 | PART A: the cancelled transaction must be rolled back (it frees Window 1)
ROLLBACK;

-- ==== STEP 7 | WINDOW 1 | RESULT | PART A: Window 1 wakes up and its UPDATE finishes
-- NOTE: Expect UPDATE 1. Window 1 was not cancelled; it just had to wait.

-- ==== STEP 8 | WINDOW 1 | PART A: Window 1 finishes Job 1 (ledger row for Shopper 2) and commits
INSERT INTO wallet_transactions (customer_id, type, amount, reason, reference) VALUES (:shopper2, 'CREDIT', 500, 'TOPUP', 'DEMO-JOB1-S2');
COMMIT;

-- ==== STEP 9 | WINDOW 2 | PART A: RETRY Job 2 from the start (the usual answer to a deadlock)
-- NOTE: This time there is no clash, because Job 1 is finished. Nothing was lost: the retry did the whole job.
BEGIN;
UPDATE customers SET wallet_balance = wallet_balance + 500 WHERE customer_id = :shopper2;
INSERT INTO wallet_transactions (customer_id, type, amount, reason, reference) VALUES (:shopper2, 'CREDIT', 500, 'TOPUP', 'DEMO-JOB2-S2');
UPDATE customers SET wallet_balance = wallet_balance + 500 WHERE customer_id = :shopper1;
INSERT INTO wallet_transactions (customer_id, type, amount, reason, reference) VALUES (:shopper1, 'CREDIT', 500, 'TOPUP', 'DEMO-JOB2-S1');
COMMIT;

-- ==== STEP 10 | WINDOW 1 | PART A, AFTER: both jobs completed, and the data is consistent
-- NOTE: Expect both wallets at 6000 (5000 + 500 + 500), each equal to its ledger total, verdict ok.
SELECT * FROM demo_wallet_check;

-- ==== PART | PART B: THE FIX (both jobs credit the shoppers in the SAME order: smallest customer id first)
-- ==== STEP 11 | WINDOW 1 | PART B: reset, and look at the BEFORE state
SELECT demo_reset_wallets();
SELECT * FROM demo_wallet_check;

-- ==== STEP 12 | WINDOW 1 | PART B: Job 1 credits Shopper 1 first (holding Shopper 1's row)
BEGIN;
UPDATE customers SET wallet_balance = wallet_balance + 500 WHERE customer_id = :shopper1;
INSERT INTO wallet_transactions (customer_id, type, amount, reason, reference) VALUES (:shopper1, 'CREDIT', 500, 'TOPUP', 'DEMO-JOB1-S1');

-- ==== STEP 13 | WINDOW 2 | WAITS | PART B: Job 2 ALSO starts with Shopper 1, so it simply waits in line
-- NOTE: Window 2 hangs, but this is a plain queue, not a circle. Window 2 holds nothing that Window 1 needs.
BEGIN;
UPDATE customers SET wallet_balance = wallet_balance + 500 WHERE customer_id = :shopper1;

-- ==== STEP 14 | WINDOW 1 | PART B: Job 1 credits Shopper 2 and commits
-- NOTE: Window 1 can finish, because Window 2 is not holding Shopper 2's row.
UPDATE customers SET wallet_balance = wallet_balance + 500 WHERE customer_id = :shopper2;
INSERT INTO wallet_transactions (customer_id, type, amount, reason, reference) VALUES (:shopper2, 'CREDIT', 500, 'TOPUP', 'DEMO-JOB1-S2');
COMMIT;

-- ==== STEP 15 | WINDOW 2 | RESULT | PART B: Window 2 wakes up (no error)
-- NOTE: Expect UPDATE 1 and NO deadlock error.

-- ==== STEP 16 | WINDOW 2 | PART B: Job 2 finishes: ledger row, then Shopper 2, then commit
INSERT INTO wallet_transactions (customer_id, type, amount, reason, reference) VALUES (:shopper1, 'CREDIT', 500, 'TOPUP', 'DEMO-JOB2-S1');
UPDATE customers SET wallet_balance = wallet_balance + 500 WHERE customer_id = :shopper2;
INSERT INTO wallet_transactions (customer_id, type, amount, reason, reference) VALUES (:shopper2, 'CREDIT', 500, 'TOPUP', 'DEMO-JOB2-S2');
COMMIT;

-- ==== STEP 17 | WINDOW 1 | PART B, AFTER: no deadlock, no retry, same final result
-- NOTE: SCREENSHOT 2: take a screenshot of this result.
-- NOTE: Expect both wallets at 6000, equal to their ledger totals, verdict ok.
SELECT * FROM demo_wallet_check;
