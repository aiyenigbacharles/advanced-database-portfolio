# portfolio-2-query-optimisation

Portfolio 2 makes the NaijaMart database fast: I load 100,000 orders of test data, measure 7 business queries, add indexes and compare the results.
Read `performance-analysis.md` first; it explains what was slow, what fixed it and what it cost.
To run it: load the seed scripts (`seed_reference.sql`, `seed_transactions.sql`, `seed_transactions_b.sql`), then run `run_all.sql` (see "How to run it" below).

## Seed design decisions

These are the choices behind `seed_transactions.sql` that I can explain if asked.

**1. Why the order status depends on the order's age**

Orders are dated between the customer's registration and a fixed "today" (15 October 2026). A delivery is picked up 3 to 27 hours after the order and arrives 1 to 4 days after that, so it can take up to about 5.6 days (a bit more after a failed attempt). If a 2 day old order were marked `DELIVERED`, its `delivered_time` would land in the future, which is impossible data. So an order can only be `DELIVERED` if it is at least 7 days old, and `SHIPPED` if it is at least 2 days old. Younger orders can only be `PENDING`, `PAID` or `CANCELLED`. The side effect is that about 87% of orders are `DELIVERED`, because most of the 100,000 orders are old. A few old orders stay `PENDING` on purpose, so there is something for a "stuck in pending" report to find. I used a fixed date instead of `now()` so the same data comes out every run.

**2. Why a cancelled order's deliveries are `PENDING` or `FAILED`**

The schema's delivery statuses are only `PENDING`, `PICKED_UP`, `DELIVERED` and `FAILED`, and its CHECK constraints tie them to the rider and the times. `DELIVERED` would say the customer got the parcel, and `PICKED_UP` would leave a parcel in transit forever, so neither fits a cancelled order. That leaves two honest stories. In 70% of cases the order was cancelled before pickup, so its deliveries stay `PENDING` with no rider and no pickup time. In the other 30% (orders at least 3 days old) a rider tried and failed, so the delivery is `FAILED` with a rider, a pickup time and 1 to 3 failed attempts, and the order was then cancelled. I chose not to add a `CANCELLED` delivery status because that would change the Portfolio 1 schema. The second case also gives the returns and refunds reports real rows to find.

**3. Why `stg_orders` is built before the orders**

Deliveries, items, payments and the wallet are all worked out from an order's final status, so the status has to be decided once, at the start. If each step drew its own random status, they would disagree (for example a `DELIVERED` order with a `PENDING` delivery). `stg_orders` is a temporary table that holds the whole plan for every order: customer, address, date, final status and item count. The `orders` table is inserted from it, and the script then checks that the two match. The temporary table disappears when the session ends, so the payments and wallet script reads the status from the real `orders` table instead. The random numbers themselves are also drawn into their own table first, in a fixed order, because otherwise the planner can hand them out in a different order depending on table statistics and the "repeatable" data would change between runs.

### Check that the seed data is the same as mine

After `seed_reference.sql`, `seed_transactions.sql` and `seed_transactions_b.sql`, the two fingerprints printed at the end of `seed_transactions_b.sql` should be:

| Fingerprint | Value |
|---|---|
| payments | `a13021805d7863168c8df8476aa16b08` |
| wallet | `c2fd260130ddab75dc591df5222c66e7` |

Row counts: 100,000 orders, 250,349 order items, 249,627 deliveries, 114,850 payments, 26,271 wallet rows.

## Optimisation work

Start with `performance-analysis.md`, which explains what was slow, what fixed it and what it cost.

| File | What it does |
|---|---|
| `queries.sql` | The 7 workload queries, each written as a business question |
| `capture_plans.sql` | Runs every query 3 times with `EXPLAIN (ANALYZE, BUFFERS)` and saves the median plan to `plans/before/` or `plans/after/` |
| `indexes.sql` / `drop_indexes.sql` | The 5 speed indexes (each with a comment on why) and the script that removes them again |
| `compare.sql` | Prints the before/after table (time, scan type, buffers) |
| `index_costs.sql` | Disk size of each index, and the time to insert 50,000 orders |
| `rewrites.sql` | Two bad-query / good-query pairs (cast on a column, correlated subquery) |
| `join_algorithms.sql` | Nested Loop vs Hash Join vs Merge Join on a small and a large join |
| `materialised_view.sql` | Q5 as a materialised view, including the staleness demo |
| `bench_helper.sql` | Shared helper that runs a query 3 times and keeps the median |
| `run_all.sql` | Runs everything above in order |
| `plans/` | Saved plans and results from the runs |

### How to run it

Load the seed data first (`seed_reference.sql`, `seed_transactions.sql`, `seed_transactions_b.sql`). Then, from this folder:

```
psql -U postgres -d ecommerce -f run_all.sql
```

This takes about a minute and rewrites everything in `plans/`. Or run the steps by hand:

```
psql -U postgres -d ecommerce -f drop_indexes.sql
psql -U postgres -d ecommerce -v phase=before -f capture_plans.sql
psql -U postgres -d ecommerce -f indexes.sql
psql -U postgres -d ecommerce -v phase=after  -f capture_plans.sql
psql -U postgres -d ecommerce -f compare.sql
```

Times depend on the computer, so the numbers in `performance-analysis.md` are from one run. The plans (which scan or join PostgreSQL chooses) and the buffer counts should be the same on other machines.
