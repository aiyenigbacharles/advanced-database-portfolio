
# portfolio-2-query-optimisation

## Seed design decisions

These are the choices behind `seed_transactions.sql` that I can explain if asked.

**1. Why the order status depends on the order's age**

Orders are dated between the customer's registration and a fixed "today" (15 October 2026). A delivery is picked up 3 to 27 hours after the order and arrives 1 to 4 days after that, so it can take up to about 5.6 days (a bit more after a failed attempt). If a 2 day old order were marked `DELIVERED`, its `delivered_time` would land in the future, which is impossible data. So an order can only be `DELIVERED` if it is at least 7 days old, and `SHIPPED` if it is at least 2 days old. Younger orders can only be `PENDING`, `PAID` or `CANCELLED`. The side effect is that about 87% of orders are `DELIVERED`, because most of the 100,000 orders are old. A few old orders stay `PENDING` on purpose, so there is something for a "stuck in pending" report to find. I used a fixed date instead of `now()` so the same data comes out every run.

**2. Why a cancelled order's deliveries are `PENDING` or `FAILED`**

The schema's delivery statuses are only `PENDING`, `PICKED_UP`, `DELIVERED` and `FAILED`, and its CHECK constraints tie them to the rider and the times. `DELIVERED` would say the customer got the parcel, and `PICKED_UP` would leave a parcel in transit forever, so neither fits a cancelled order. That leaves two honest stories. In 70% of cases the order was cancelled before pickup, so its deliveries stay `PENDING` with no rider and no pickup time. In the other 30% (orders at least 3 days old) a rider tried and failed, so the delivery is `FAILED` with a rider, a pickup time and 1 to 3 failed attempts, and the order was then cancelled. I chose not to add a `CANCELLED` delivery status because that would change the Portfolio 1 schema. The second case also gives the returns and refunds reports real rows to find.

**3. Why `stg_orders` is built before the orders**

Deliveries, items, payments and the wallet are all worked out from an order's final status, so the status has to be decided once, at the start. If each step drew its own random status, they would disagree (for example a `DELIVERED` order with a `PENDING` delivery). `stg_orders` is a temporary table that holds the whole plan for every order: customer, address, date, final status and item count. The `orders` table is inserted from it, and the script then checks that the two match. The temporary table disappears when the session ends, so the payments and wallet script reads the status from the real `orders` table instead.
