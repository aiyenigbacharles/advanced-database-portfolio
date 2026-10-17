
# Normalisation: NaijaMart

**Course:** MIT 8103 Advanced Database Systems, Portfolio 1
**Database:** PostgreSQL, 11 tables (see `schema.sql` and `erd.png`)

This file shows how the NaijaMart design was reached step by step through 1NF, 2NF and 3NF, checks each final table, and lists the few places where the design **deliberately** breaks the rules and what keeps those places correct.

---

1. Why normalise at all

Normalisation means storing each fact in one place only. If a fact is stored in many places, three problems appear:

| Problem                  | Example at NaijaMart if seller details were copied onto every product row                                                      |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| **Update anomaly** | A seller changes phone number. A seller with 400 products means 400 rows to edit. Miss one and the data disagrees with itself. |
| **Insert anomaly** | A new seller cannot be saved until they list a product, because the seller only exists inside product rows.                    |
| **Delete anomaly** | Deleting a seller's last product also deletes every trace of the seller, including their bank details.                         |

---

## 2. Starting point: one flat sheet

Imagine NaijaMart began with a single spreadsheet. Amaka's order (a Tecno phone from Lagos and ofada rice from Ibadan) would look like this:

| order_id | order_date | customer_name | customer_email | customer_address             | items                                           | seller_names                 | seller_cities | rider        | payment    |
| -------- | ---------- | ------------- | -------------- | ---------------------------- | ----------------------------------------------- | ---------------------------- | ------------- | ------------ | ---------- |
| 1        | 2026-10-01 | Amaka Obi     | amaka@mail.com | 12 Gwarinpa Road, Abuja, FCT | Tecno Spark x1 at 85000; Ofada Rice x1 at 12000 | Lagos Gadgets; Ibadan Grains | Lagos; Ibadan | Ibrahim Sule | CARD 97000 |

Problems: several items and sellers are crammed into one cell, the address is one block of text, and customer and seller facts repeat for every order.

---

## 3. First Normal Form (1NF): one value per cell, no repeating groups

**Rule:** every cell holds a single value, and there are no lists inside a cell.

**What changed:**

- The `items` cell becomes **one row per item**. That is the `order_items` table.
- The address text is split into `street`, `landmark`, `city` and `state`, so Abuja deliveries can be counted by state.
- Seller names and cities are no longer lists. Each seller is its own row.
- Every table gets a primary key (identity column), so each row can be told apart.

After 1NF the data is atomic, but facts still repeat. The next two steps remove that.

---

## 4. Second Normal Form (2NF): no partial dependency on part of a key

**Rule:** the table is in 1NF, and every non-key column depends on the **whole** key, not just part of it.

**Where it applied:** the item rows from step 3 have the key (order_id, product_id). But:

| Column                                    | Depends on                        | Problem                                           |
| ----------------------------------------- | --------------------------------- | ------------------------------------------------- |
| customer_name, customer_email, order_date | `order_id` only                 | Repeated on every item row of the same order      |
| product_name, seller, category            | `product_id` only               | Repeated on every order that contains the product |
| quantity                                  | the whole key (order and product) | This one correctly stays                          |

**What changed:**

- Order facts move to `orders`.
- Product facts move to `products`.
- `order_items` keeps only what truly belongs to "this product in this order": quantity, and the price and commission frozen at purchase time (see section 7).

---

## 5. Third Normal Form (3NF): no dependency through a non-key column

**Rule:** the table is in 2NF, and no non-key column depends on another non-key column. Every fact depends on "the key, the whole key, and nothing but the key".

**Chains removed:**

| Chain                                                        | Meaning                                                      | Fix                                                                                    |
| ------------------------------------------------------------ | ------------------------------------------------------------ | -------------------------------------------------------------------------------------- |
| product_id to seller_id to business_name, city, bank         | Seller details are really facts about the seller             | `sellers` table. `products` keeps only `seller_id`.                              |
| product_id to category_id to commission_rate                 | Commission is a fact about the category                      | `categories` table (also holds the sub-category link through `parent_category_id`) |
| order_id to customer_id to name, email, phone                | Customer facts depend on the customer, not the order         | `customers` table                                                                    |
| order_id to address_id to street, city, state                | Address facts depend on the address                          | `addresses` table                                                                    |
| order_id to seller_id to rider, pickup time, delivery status | Delivery facts belong to one seller's parcel inside an order | `deliveries` table, one row per seller per order                                     |
| order_id to payment method, amount, reference                | A payment is its own event, and one order can have several   | `payments` table                                                                     |

Result: an address change, a seller phone change or a commission change is **one row edit**.

---

## 6. Final check, table by table

For each table the question is: does every non-key column depend only on the key?

| Table                   | Key           | Other keys (UNIQUE)                            | Result                                                                                                                                       |
| ----------------------- | ------------- | ---------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `customers`           | customer_id   | email, phone                                   | 3NF. Every column describes the customer. `wallet_balance` is a deliberate cached value (section 7).                                       |
| `addresses`           | address_id    | none                                           | 3NF. `city` and `state` are both stored. A city name alone does not reliably decide a state across Nigeria, so no dependency is assumed. |
| `sellers`             | seller_id     | email                                          | 3NF. Bank name and account number are stored together because an account number only means something with its bank.                          |
| `categories`          | category_id   | name                                           | 3NF. `commission_rate` is the current rate for the category.                                                                               |
| `products`            | product_id    | (product_id, seller_id)                        | 3NF. The extra UNIQUE is only a target for a composite foreign key.                                                                          |
| `riders`              | rider_id      | phone                                          | 3NF. `courier_company` is kept as plain text because no other company facts are stored.                                                    |
| `orders`              | order_id      | none                                           | 3NF except `total_amount`, a deliberate derived value (section 7).                                                                         |
| `deliveries`          | delivery_id   | (order_id, seller_id), (order_id, delivery_id) | 3NF. All determinants are keys.                                                                                                              |
| `order_items`         | order_item_id | (order_id, product_id)                         | 3NF except the deliberate copies in section 7.                                                                                               |
| `payments`            | payment_id    | reference                                      | 3NF except the deliberate `delivery_id` and `order_id` pair (section 7).                                                                 |
| `wallet_transactions` | wallet_txn_id | reference                                      | 3NF. A ledger row is one event.                                                                                                              |

---

## 7. Deliberate denormalisation (and why it is safe)

These break strict 3NF **on purpose**. Each one is either a **historical snapshot** (the source may change, the copy must not) or a **derived value** (kept for speed, with a check). Each one also says what stops it from drifting.

| What is stored                       | Where           | Source of truth                                      | Kind           | Why it is kept                                                                                     | What keeps it correct                                                                                        |
| ------------------------------------ | --------------- | ---------------------------------------------------- | -------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `unit_price`                       | `order_items` | `products.price` at the moment of sale             | Snapshot       | Prices change. An old order must show what the customer actually paid.                             | Copied once at creation, never updated.                                                                      |
| `commission_rate`                  | `order_items` | `categories.commission_rate` at the moment of sale | Snapshot       | If the fashion rate drops from 10% to 8%, past payouts must not change.                            | Copied once, never updated. Payout = `unit_price * quantity * (1 - commission_rate)`.                      |
| `seller_id`                        | `order_items` | `products.seller_id`                               | Redundant copy | Lets the database prove that the item, the product and the delivery agree on one seller.           | Two composite foreign keys (below). A mismatch cannot be saved.                                              |
| `delivery_id` next to `order_id` | `payments`    | `deliveries.order_id`                              | Redundant pair | Online payments cover a whole order, so they need `order_id`. Cash payments need their delivery. | Composite foreign key `(order_id, delivery_id)`. A payment cannot point at another order's delivery.       |
| `total_amount`                     | `orders`      | Sum of `unit_price * quantity` over the items      | Derived        | Fast order lists, receipts and reports with no join.                                               | Set in the same transaction that inserts the items. Audit query below.                                       |
| `wallet_balance`                   | `customers`   | Credits minus debits in `wallet_transactions`      | Derived        | Fast balance check at checkout, and one row to lock so two payments cannot spend the same money.   | Changed in the same transaction as each ledger row, with `CHECK (wallet_balance >= 0)`. Audit query below. |

### How the composite foreign keys work

| Key                                     | Points to                              | What it guarantees                                                                                                       |
| --------------------------------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `order_items (product_id, seller_id)` | `products (product_id, seller_id)`   | The product really belongs to the seller named on the item.                                                              |
| `order_items (order_id, seller_id)`   | `deliveries (order_id, seller_id)`   | That seller has a delivery in this order, and the item sits in it.                                                       |
| `payments (order_id, delivery_id)`    | `deliveries (order_id, delivery_id)` | A cash payment names a delivery from its own order. When `delivery_id` is empty (online payments) this key is skipped. |

One side effect: a product that already has sales cannot be moved to another seller. If a listing really changes hands, it becomes a new product row.

### Audit queries for the two derived values

These return rows only when something has drifted, so an empty result means the data is consistent. They are written for Portfolio 3 and have not been run yet.

```sql
-- orders.total_amount versus the recalculated sum of its items
SELECT o.order_id, o.total_amount,
       COALESCE(SUM(oi.unit_price * oi.quantity), 0) AS recalculated
FROM orders o
LEFT JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY o.order_id, o.total_amount
HAVING o.total_amount <> COALESCE(SUM(oi.unit_price * oi.quantity), 0);

-- customers.wallet_balance versus the ledger
SELECT c.customer_id, c.wallet_balance,
       COALESCE(SUM(CASE WHEN w.type = 'CREDIT' THEN w.amount ELSE -w.amount END), 0) AS ledger_balance
FROM customers c
LEFT JOIN wallet_transactions w ON w.customer_id = c.customer_id
GROUP BY c.customer_id, c.wallet_balance
HAVING c.wallet_balance <> COALESCE(SUM(CASE WHEN w.type = 'CREDIT' THEN w.amount ELSE -w.amount END), 0);
```

---

## 8. Rules the database enforces itself

| Rule                                                                | How                                                                                                                  |
| ------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| A product belongs to exactly one seller.                            | `products.seller_id` is `NOT NULL`.                                                                              |
| An item names the same seller as its product.                       | Composite foreign key to `products (product_id, seller_id)`.                                                       |
| An item sits in the delivery from its own seller, in its own order. | Composite foreign key to `deliveries (order_id, seller_id)`. This also means one delivery per seller per order.    |
| Deliveries exist before their items.                                | Order placement inserts the order, then one `PENDING` delivery per seller, then the items, all in one transaction. |
| A Pay on Delivery payment is tied to its delivery.                  | `delivery_id` is filled exactly when the method is `POD`, plus the composite key above.                          |
| Stock, prices, quantities and amounts make sense.                   | `CHECK` constraints (stock at least 0, quantity above 0, price above 0, payment amount above 0).                   |
| A delivery's times and status agree.                                | `CHECK` constraints on pickup time, delivery time, rider and attempts.                                             |
| Financial history is never erased.                                  | `ON DELETE RESTRICT` on orders, items, payments, deliveries and wallet rows.                                       |

Each rule has at least one failing statement in `constraint_tests.sql`.

---

## 9. What the constraints cannot do

Being honest about limits is part of the design:

- Nothing in the schema forces `orders.total_amount` or `customers.wallet_balance` to match their sources. They rely on the transaction rule and the audit queries.
- Nothing stops two customers buying the last item at the same moment. That is a concurrency problem, handled in Portfolio 3.
- An order can currently point at an address that belongs to a different customer. A third composite key on `addresses (address_id, customer_id)` would close this gap. It is noted here as a known gap.
