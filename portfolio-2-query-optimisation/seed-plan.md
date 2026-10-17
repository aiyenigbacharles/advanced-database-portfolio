# Seed Plan: loading NaijaMart test data

**Portfolio 2, query optimisation.** Query plans only mean something with realistic volumes, so the database is filled with simulated data before any query is timed.

**Target volumes (from the case study):** 25,000 customers, 500 sellers, 8,000 products, 100,000 orders, about 250,000 order items, 100,000 payments.

The foreign keys decide the order. A row can only be inserted after every row it points at already exists.

---

## The load order

### Part 1: reference data (`seed_reference.sql`)

| Step | Load | Reason |
|---|---|---|
| 1 | Empty all 11 tables and restart the id counters | Makes the script repeatable, and ids always start at 1 so later scripts can rely on them. |
| 2 | Top level categories, then sub-categories | `categories` points at itself, so a parent must exist before its children. |
| 3 | Sellers | They depend on nothing, and products need them. |
| 4 | Products | Each needs a seller and a category. Only approved sellers get products, and only sub-categories are used. |
| 5 | Customers | They depend on nothing. `wallet_balance` starts at 0 because the wallet ledger does not exist yet. |
| 6 | Addresses | Each needs a customer. Every customer gets exactly one default address, some get a second. |
| 7 | Riders | They depend on nothing, and deliveries need them. |

### Part 2: transactions (`seed_transactions.sql`, next)

| Step | Load | Reason |
|---|---|---|
| 8 | Orders, with `total_amount` set to 0 for now | Each needs a customer and an address. The script must pick the customer's own address, because the schema does not check that. The total is unknown until the items exist. |
| 9 | A staging table of planned items (order, product, seller taken from the product, quantity, price and commission copied from the product and its category) | Which sellers appear in an order decides how many deliveries it needs, so items are chosen before deliveries are created. |
| 10 | Deliveries: one row for each distinct (order, seller) pair in the staging table | `order_items` points at `deliveries (order_id, seller_id)`, so the delivery must exist first. This also guarantees one delivery per seller per order. |
| 11 | Order items, copied from the staging table | Both composite foreign keys can now be satisfied. |
| 12 | Update `orders.total_amount` from the items | The total can only be calculated once the items exist. |
| 13 | Payments | They need an order. Online payments cover the whole order. Pay on Delivery payments need a delivery, one for each delivery. |
| 14 | Wallet transactions, then set `customers.wallet_balance` to the ledger total. Create each customer's credits (top-ups and refunds) first, then add debits (purchases) only while the balance can cover them. | The ledger is the source of truth, so the cached balance is calculated from it and the audit query comes back clean. Credits must be at least the debits for every customer, so no balance is ever below 0 (the schema would reject it anyway). |
| 15 | `ANALYZE` on every table | PostgreSQL's planner needs fresh statistics, or the query plans will not reflect this data. |
| 16 | Verification: row counts, the two audit queries, and the payment and status checks from the rules below | Proves the data is complete and consistent before any timing starts. |

---

## Rules part 2 must follow

- An order's date comes after its customer's `registered_at`.
- A delivery's status agrees with its order's status, and its times follow the schema rules (a rider and a pickup time once started, `delivered_time` only when delivered, never before pickup).
- A Pay on Delivery payment names a delivery that belongs to the same order.
- **Payments must reconcile.** An online payment (card, transfer, USSD or wallet) has an amount equal to its order's `total_amount`. A Pay on Delivery payment has an amount equal to the sum of `unit_price * quantity` for the items in its own delivery. Otherwise finance queries (sales, payouts, audits) return numbers that mean nothing. For an order paid entirely on delivery, its payments add up to the order total.
- **Statuses must agree across tables.** The payment status has to make sense for the order status:

  | Order status | Payment status allowed |
  |---|---|
  | `PENDING` | `PENDING` or `FAILED`. Never `SUCCESS`. |
  | `PAID` or `SHIPPED` | Online payments are `SUCCESS`. Pay on Delivery payments are still `PENDING`, because the cash has not been collected yet. |
  | `DELIVERED` | `SUCCESS`. Pay on Delivery cash is collected at delivery. |
  | `CANCELLED` | `FAILED`, or `REFUNDED` if the money had already been paid. |

  Pay on Delivery orders never use `PAID`. They go from `PENDING` to `SHIPPED` to `DELIVERED`.
  `paid_at` is filled only for `SUCCESS` and `REFUNDED` payments, and is never earlier than the order date. The schema already enforces the first half of that rule, so a mistake here makes the script fail.
- **The wallet can never go negative.** For every customer, total credits are at least total debits. The ledger is built in date order and a debit is only added while the running balance can cover it, so the balance is never below 0, not even in the middle of the history.
- Seeded orders do not reduce product stock. Stock numbers are independent random values, so stock cannot be audited against orders. This is a known limit of the test data.

## Rules for the whole seed

- Every value must pass the schema constraints, so the script is also a bulk test of them.
- `setseed(0.42)` runs first, so the same data comes out every time.
- No speed indexes are created yet. The baseline query plans (Portfolio 2) must be captured first, so the before and after comparison is fair.
