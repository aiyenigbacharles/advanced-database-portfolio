# Portfolio 2: Performance Analysis

**Case study:** NaijaMart, an online marketplace. **Data:** 100,000 orders, about 250,000 order items, 250,000 deliveries, 115,000 payments. **Database:** PostgreSQL. All times are in milliseconds (ms).

## 1. Summary in plain words

I wrote 7 queries a real business would ask (`queries.sql`) and measured each one on a database that has **no extra indexes**, only the primary and unique keys. Five of the seven were slow for the same reason: PostgreSQL had no index to find the right rows, so it **read the whole table** and threw most of it away. Five small indexes (`indexes.sql`) fixed those five. The other two (Q4 and Q5) are reports that must read most of the data, so **no index can help them**. A **materialised view** fixed those instead.

| What was wrong | What fixed it | Result |
|---|---|---|
| Looking up one customer, one seller or one rider's rows meant scanning the whole table | An index that starts with that column | 2.5 to 119 times faster |
| A big report re-adds 218,000 rows on every run | Store the answer once (materialised view) | 305 ms down to 2 ms |
| Two badly written queries | Rewrite them | 18 and 8 times faster |

## 2. How I measured

- Each query is run **3 times** with `EXPLAIN (ANALYZE, BUFFERS)` and I keep the **median** (middle) time. One slow first run (cold cache) cannot distort the result.
- `drop_indexes.sql` and `indexes.sql` are a pair, so "before" and "after" are repeatable. `run_all.sql` does the whole sequence in about a minute.
- The seed data has a fixed "today" (15 October 2026) and the seed is repeatable, so the queries use that date, not `now()`.
- **Buffers** = the number of 8 kB pages PostgreSQL had to touch. It is a steadier measure than time, because time changes a little from run to run.
- Plans are saved in `plans/before/`, `plans/after/` and the other `plans/` folders.

## 3. Results: before and after

| Query | Question | Before ms | After ms | Times faster | Buffers before to after | How it was answered before, then after |
|---|---|---|---|---|---|---|
| Q1 | One customer's last 20 orders | 4.400 | 0.037 | 119 | 1,754 to 30 | Seq Scan on orders, then Bitmap Index Scan on `idx_orders_customer_date` |
| Q2 | Orders PENDING for over 2 days | 5.657 | 2.275 | 2.5 | 1,754 to 883 | Seq Scan on orders, then Bitmap Index Scan on `idx_orders_pending_date` |
| Q3 | One seller's items, last 30 days | 17.345 | 1.910 | 9.1 | 4,270 to 2,869 | Parallel Seq Scan on order_items, then Bitmap Index Scan on `idx_order_items_seller_order` |
| Q4 | Top 10 products, last 90 days | 146.501 | 151.973 | 1.0 | 3,859 to 3,859 | Seq Scans, unchanged |
| Q5 | Monthly commission per seller | 288.457 | 284.065 | 1.0 | 4,747 to 4,747 | Seq Scans, unchanged |
| Q6 | Riders with most FAILED deliveries | 19.463 | 1.014 | 19 | 2,795 to 10 | Parallel Seq Scan on deliveries, then **Index Only Scan** on `idx_deliveries_failed_rider` |
| Q7 | One customer's wallet history | 1.242 | 0.014 | 89 | 285 to 7 | Seq Scan on wallet_transactions, then Bitmap Index Scan on `idx_wallet_customer_date` |

How to read it:

- **Q1, Q6 and Q7** were the clearest wins. They need a tiny part of a big table (28 of 100,000 rows, 3,072 of 249,627 deliveries, 10 of 26,000 wallet rows). The buffer count dropping from thousands to a handful shows PostgreSQL stopped reading the table.
- **Q2 only improved 2.5 times**, and that is expected. It really returns 2,568 orders, and the pending orders are scattered across the whole table, so PostgreSQL still has to visit about half of the table's pages (883 of 1,754). An index helps most when the answer is small.
- **Q3 improved 9 times.** It no longer scans all 250,000 items. The remaining cost is looking up each item's order and product.
- **Q4 and Q5 did not change.** The plan is identical, so the small differences in time (1.0 times) are just noise between runs. I tested extra indexes on them (`orders (order_date, status)`, `order_items (product_id)` and a covering index on `order_items (order_id)`). PostgreSQL ignored them and still scanned the tables (181 ms and 320 ms), because Q4 reads about half of all orders and Q5 reads every delivered order. When a query needs most of a table, reading it in order is cheaper than jumping around through an index.

## 4. The five indexes: what each one fixed

| Index | Type | Fixes | Why it is built this way |
|---|---|---|---|
| `idx_orders_customer_date` on `orders (customer_id, order_date DESC)` | Composite | Q1 | `customer_id` first because the query tests it with `=`. `order_date` second because the query sorts by it, so one customer's orders are together and already in date order. |
| `idx_orders_pending_date` on `orders (order_date) WHERE status = 'PENDING'` | **Partial** | Q2 | Only 3.4% of orders are PENDING, so the index holds only those rows. It is tiny (96 kB). The query must say `status = 'PENDING'` for PostgreSQL to use it. |
| `idx_order_items_seller_order` on `order_items (seller_id, order_id)` | Composite | Q3 | `seller_id` first for `WHERE seller_id = 33`. `order_id` second because it is the join key to `orders`. |
| `idx_deliveries_failed_rider` on `deliveries (rider_id) WHERE status = 'FAILED'` | **Partial** | Q6 | Only 1.2% of deliveries are FAILED. The query groups by `rider_id` and needs nothing else, so the index alone answers it (Index Only Scan, 10 buffers). |
| `idx_wallet_customer_date` on `wallet_transactions (customer_id, created_at DESC)` | Composite | Q7 | Same pattern as Q1. |

Column order matters in a composite index. The rule I followed: columns tested with `=` go first, then the column used for sorting or joining. An index on `(order_date, customer_id)` would not help Q1, because the rows for one customer would be scattered through the index.

One detail: on some runs the planner reads Q1's index and sorts the 28 rows itself, and on other runs it reads them already sorted. It guesses from statistics (it expects about 5 orders for an average customer, and customer 10 has 28). Either way it reads about 30 pages, so the result is the same.

## 5. What the indexes cost

| Cost | Without the new indexes | With them |
|---|---|---|
| Disk space (all 5 indexes) | 0 | **9.4 MB** extra (the 11 tables take about 71 MB) |
| Time to insert 50,000 orders (median of 3) | **65 ms**, with none of the 2 new `orders` indexes | **108 ms**, with the 2 indexes that apply to `orders` (about 1.7 times slower) |

The write test inserts into a copy of the `orders` table, so it only measures the **2 indexes that apply to `orders`** (`idx_orders_customer_date` and `idx_orders_pending_date`). The other 3 indexes sit on other tables (`order_items`, `deliveries`, `wallet_transactions`), and I did not time inserts into those.

Size of each index: `idx_order_items_seller_order` 5,512 kB, `idx_orders_customer_date` 3,104 kB, `idx_wallet_customer_date` 824 kB, `idx_orders_pending_date` 96 kB, `idx_deliveries_failed_rider` 48 kB.

- **Every index must be updated on every INSERT, UPDATE and DELETE.** With just the 2 indexes that apply to `orders`, inserting into that table got about 1.7 times slower. That is a fair price for NaijaMart, which reads orders far more often than it writes them, but it is a real cost.
- **Partial indexes are the cheapest.** The two partial indexes together are 144 kB, because they only contain the 1 to 3% of rows that matter. A row that is not PENDING never touches `idx_orders_pending_date`.
- I did **not** index things no query asks for (for example `orders.status` alone). Each unused index would cost space and write time for no benefit.

## 6. Two query-processing ideas

### Rewrite 1: a function on the column (`::date`) versus a range

Question: how many orders were placed on 10 October 2026? (An index on `order_date` exists for this test only, and is dropped afterwards.)

| Version | Query | Median ms | Plan | Buffers |
|---|---|---|---|---|
| Bad | `WHERE order_date::date = '2026-10-10'` | 10.293 | Seq Scan, 98,987 rows thrown away | 1,754 |
| Good | `WHERE order_date >= '2026-10-10' AND order_date < '2026-10-11'` | 0.585 | Bitmap Index Scan | 626 |

**Why:** the index is sorted by the original timestamps. The `::date` cast changes every value before the comparison, so PostgreSQL cannot use the index to jump to the right place. It has to apply the cast to all 100,000 rows. Writing the same condition as a plain range leaves the column untouched, so the index can be used. Both return the same answer (1,013 orders, 176,454,700 naira). The rule is: **do not wrap an indexed column in a function; move the work to the other side of the comparison.**

### Rewrite 2: a correlated subquery versus a join

Question: which orders are bigger than that customer's own average order?

| Version | Median ms | How it runs | Buffers |
|---|---|---|---|
| Bad: correlated subquery | 826.021 | The subquery runs 100,000 times, once per order (`loops=100000`) | 838,452 |
| Good: `GROUP BY` once, then `JOIN` | 98.401 | One pass computes every customer's average, then one Hash Join | 3,508 |

**Why:** the bad version refers to `o.customer_id` from the outer query, so the subquery cannot be calculated once. It is repeated for every order. The good version computes all 24,375 customer averages in a single pass and joins them. The results are identical (checked with `EXCEPT`, 0 rows differ). The bad version was only run with `idx_orders_customer_date` in place. Without it, each of the 100,000 repeats would scan the whole table, which would take far too long.

### Join algorithms (same query, three methods)

PostgreSQL normally chooses the join method. I forced each one in turn with `SET enable_hashjoin = off` and similar settings (then `RESET`). Parallel workers were switched off for this test.

| Query | Nested Loop | Hash Join | Merge Join | The planner chose |
|---|---|---|---|---|
| **J1 small:** one customer's orders with items (28 orders) | **0.106 ms** (142 buffers) | 31.322 ms (1,871) | 37.302 ms (2,397) | Nested Loop |
| **J2 large:** item revenue for the last 90 days (about 52,000 orders) | 161.212 ms (208,861) | **95.476 ms** (3,595) | 109.144 ms (4,075) | Hash Join |

- **Nested Loop** takes each outer row and looks up its matches through an index. With 28 outer rows that is 28 quick lookups, so it wins by a huge margin. With 52,000 outer rows it makes 52,000 lookups (208,861 buffer touches) and loses.
- **Hash Join** reads one side once into an in-memory hash table and probes it with the other side. It has a start-up cost (building the table), which is why it is 300 times slower on the small query, but it wins on the large one.
- **Merge Join** sorts both sides and walks through them together. It is never the winner here because neither side arrives already sorted, so the sorting is extra work.

The best join depends on **how many rows** are involved, and the planner picks it from its row estimates. That is why fresh statistics (`ANALYZE`) matter. In both cases the planner's own choice matched the fastest method.

## 7. Materialised view for Q5 (monthly commission)

`mv_monthly_commission` stores the answer to Q5 as a real table (9,304 rows, 512 kB).

| | Median ms | Buffers |
|---|---|---|
| Q5 run directly (adds up 218,578 rows; the sort spills 9 MB to disk) | **305.533** | 3,595 plus temporary disk files |
| Same answer read from the view | **2.286** (134 times faster) | 9,204 |
| One seller's months from the view (a seller dashboard) | **0.044** | 19 |

The view reads more buffers (9,204) than the direct query (3,595), yet it is 134 times faster. That is because the view is read through its index, so each row touches an index page and a heap (table) page. It is faster because it skips the join, the aggregation and the 9 MB disk spill, not because it touches fewer pages.

The view and the direct query return identical rows (0 rows differ). Creating the view took about 204 ms, and a refresh takes about 178 ms.

**The catch: the view goes stale.** The staleness demo (`plans/matview/staleness_demo.txt`, rolled back so no real data changes) shows it:

| Step | View | Live query |
|---|---|---|
| Start | 1,085,915.00 | 1,085,915.00 |
| After one order item's quantity changes | **1,085,915.00 (stale)** | 1,106,460.00 |
| After `REFRESH MATERIALIZED VIEW` | 1,106,460.00 | 1,106,460.00 |

So a materialised view is a good fit when the data is read often, changes slowly and can be a little out of date. Monthly commission fits well: it is a finance report, and a month's numbers settle once its orders are delivered. In practice I would refresh it every night with `REFRESH MATERIALIZED VIEW CONCURRENTLY` (the unique index I created allows it, and readers are not blocked while it runs). It would not suit something that must be exact at every second, such as an account balance. This is the same idea as caching with Redis (Portfolio 4, NoSQL), but inside the database, so the refresh strategy is the thing to design.

## 8. Limits of these measurements

- The whole database (about 71 MB) fits in memory, so almost every read is a cache hit. On a larger database or a cold cache, the full-table scans would be much slower and the indexes would look even better. The buffer counts are the fairer comparison.
- Times vary a little from run to run, which is why I use the median of 3 and show buffers. Q4 and Q5 changed by about 1% only because they ran the same plan.
- The write-cost test measures inserts only, on the `orders` table and its 2 indexes. Updates and deletes also maintain indexes, and I did not time those.
- The workload is 7 queries. A different workload would justify different indexes.
