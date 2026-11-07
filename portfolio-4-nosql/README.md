# Portfolio 4: NoSQL and Advanced Data Models

NaijaMart keeps its money data (orders, payments, wallet, price, stock) in PostgreSQL, where transactions keep it exact. This portfolio adds the data that does not fit neatly into tables: the **product catalogue and reviews** go into **MongoDB** (documents), the **shopping cart** is designed for **Redis** (key-value), and a **"customers also bought"** feature is explained as a **graph** idea.

Start with `design.md`, which explains every decision in plain words. This README shows the models, the evidence and the trade-offs.

## The three data models

| Model               | Used for                | Tool        | Status             |
| ------------------- | ----------------------- | ----------- | ------------------ |
| **Document**  | Products and reviews    | MongoDB     | built and measured |
| **Key-value** | Shopping carts          | Redis       | done               |
| **Graph**     | "Customers also bought" | (idea only) | explained below    |

### 1. Document model (MongoDB): products and reviews

A phone has RAM and storage, a dress has sizes and colours, rice has a weight. In one PostgreSQL table, most columns would be empty on every row. In MongoDB each product document simply holds the fields it has, inside an `attributes` block.

**A product document** (a phone; `product_id` is the link to PostgreSQL):

```js
{
  product_id: 4,
  name: 'Refurbished iPhone 11 Mini',
  brand: 'Apple',
  description: 'Refurbished iPhone 11 Mini by Apple. ... Details: ram gb: 4; storage gb: 64; ...',
  category: 'Smartphones',
  parent_category: 'Phones',
  seller_id: 130,
  attributes: { ram_gb: 4, storage_gb: 64, battery_mah: 4000, screen_inches: 6.5, network: '4G', dual_sim: false },
  price_ngn: 528900,                                  // a COPY of the PostgreSQL price
  price_synced_at: ISODate('2026-10-15T00:00:00.000Z'),
  rating_avg: 4.05,
  rating_count: 19
}
```

**The `attributes` block of a fashion product**, with completely different fields:

```js
attributes: { sizes: ['S', 'M', 'L', 'XXL'], colours: ['Brown', 'Purple'], fabric: 'Ankara', gender: 'Women' }
```

**A review document** (in its own collection, pointing to the product):

```js
{
  product_id: 4,                // the link to the product
  customer_id: 23421,           // the link to a PostgreSQL customer
  rating: 4,
  title: 'Happy with it',
  comment: 'Happy overall, would recommend.',
  helpful_votes: 25,
  verified_purchase: true,
  created_at: ISODate('2025-05-21T12:44:27.558Z')
}
```

Reviews are **not** stored inside the product, because a popular product could get tens of thousands of them and one MongoDB document is limited to 16 MB. The product keeps only a small summary (`rating_avg` and `rating_count`), which is worked out from the real reviews.

### 2. Key-value model (Redis): the shopping cart

The cart changes with every tap, must load instantly, and does not need to last forever, which is what a key-value store is for. The design (see `design.md`, section 5):

- One key per customer: `cart:<customer_id>`, holding a **hash** of `product_id` to quantity.
- An **expiry time** on the key: about 7 days after the last change in real use, and 60 seconds in the demo so the expiry can be seen.
- Only product ids and quantities, never prices. The price is read from PostgreSQL at checkout.

```
HSET cart:25001 2 1            # customer 25001 adds 1 of product 2
HSET cart:25001 4 1            # and 1 of product 4
EXPIRE cart:25001 604800       # the cart disappears after 7 days of no activity
HGETALL cart:25001             # show the cart
TTL cart:25001                 # seconds left before it expires
```

These are the planned commands. The demo with real output is in `redis_cart_demo.md`.

### 3. Graph model (idea only): "customers also bought"

The case study wants to suggest products ("customers who bought a phone also bought a case"). That is a question about **relationships**: customers are connected to the products they bought, and products are connected to each other through shared customers. In PostgreSQL this means joining `order_items` to itself again for every hop, and each extra hop makes the query slower and harder to write. A **graph database** such as Neo4j stores the connections themselves, so following them is natural:

```
MATCH (c:Customer)-[:BOUGHT]->(:Product {id: 4})        // customers who bought product 4
MATCH (c)-[:BOUGHT]->(other:Product) WHERE other.id <> 4 // what else they bought
RETURN other.name, count(*) AS bought_together
ORDER BY bought_together DESC LIMIT 5;
```

This query is an illustration written in Neo4j's language (Cypher). **I did not build or run a graph database.** Suggestions are fine to be a few seconds late, so they could be rebuilt from PostgreSQL orders in the background (the eventual-consistency choice in section 6 of the case study).

## What goes where

| Data                                   | Database     | Why                                                                    |
| -------------------------------------- | ------------ | ---------------------------------------------------------------------- |
| Orders, payments, wallet, price, stock | PostgreSQL   | Money must be exact, and these follow ACID rules                       |
| Product catalogue and reviews          | MongoDB      | Different fields per category, and reviews that can grow without limit |
| Shopping cart                          | Redis        | Fast reads and writes, and carts can expire                            |
| "Customers also bought"                | Graph (idea) | Based on relationships                                                 |

## The files in this folder

| File                                             | What it is                                                                                                       |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| `design.md`                                    | The design: catalogue fields, embed or reference, source of truth, the three queries that must be fast, the cart |
| `export_products.sql`                          | Exports the 8,000 products from PostgreSQL into `data/products_export.json`                                    |
| `data/products_export.json`                    | The exported products (the input for the seed script)                                                            |
| `seed_mongo.js`                                | Builds the product documents and the reviews, and loads them into MongoDB                                        |
| `explain_queries.js`                           | Runs the three queries with `explain` and prints how much work MongoDB did                                     |
| `indexes_mongo.js` / `drop_indexes_mongo.js` | Create the indexes, and remove them again for repeatable before and after runs                                   |
| `export_prices.sql`                            | Exports the current PostgreSQL prices into `data/prices_now.json`                                              |
| `sync_prices.js`                               | Copies changed prices from PostgreSQL into MongoDB                                                               |
| `plans/`                                       | Saved results: `mongo_before.txt`, `mongo_after.txt` and `mongo_q1_index_comparison.txt`                   |
| `screenshots/`                                 | Screenshots of the work                                                                                          |

## How to run it

You need PostgreSQL (with the `ecommerce` database from Portfolios 1 and 2) and MongoDB with `mongosh`. I used MongoDB 9.0.4 and mongosh 2.13.0 on Windows. Open PowerShell in this folder.

**1. Export the products** (skip this if `data/products_export.json` is already there):

```
psql -U postgres -d ecommerce -At -f export_products.sql -o data\products_export.json
```

**2. Load MongoDB.** This drops and recreates the `products` and `reviews` collections in `naijamart`, so you can run it as often as you like:

```
mongosh "mongodb://localhost:27017/naijamart" --file seed_mongo.js
```

It should end with 8000 products, 67544 reviews, and a refused duplicate `product_id`. The data is **repeatable**: the same seed always gives the same data.

**3. BEFORE: measure the queries with no indexes:**

```
mongosh "mongodb://localhost:27017/naijamart" --file explain_queries.js | Out-File -Encoding utf8 plans\mongo_beforext.txt
Get-Content plans\mongo_before.txt
```

**4. Create the indexes:**

```
mongosh "mongodb://localhost:27017/naijamart" --file indexes_mongo.js
```

**5. AFTER: measure again:**

```
mongosh "mongodb://localhost:27017/naijamart" --file explain_queries.js | Out-File -Encoding utf8 plans\mongo_after.txt
Get-Content plans\mongo_after.txt
```

To go back to the "before" state, run `drop_indexes_mongo.js`.

## The three queries and what the indexes did

Each query is run 3 times and the middle time is kept. Times vary a little from run to run, so this table uses the steadier numbers: how many index entries (**keys**) and documents MongoDB had to read. The times are in `plans/`.

| Query                                                                                 | Before (no index)                                       | After (with index)                                |
| ------------------------------------------------------------------------------------- | ------------------------------------------------------- | ------------------------------------------------- |
| **Q1** Phones with 8 GB RAM or more, up to ₦300,000, cheapest first (first 20) | Read all 8,000 documents (`COLLSCAN`) and sorted them | Read about 267 index keys and only 20 documents   |
| **Q2** The 10 best-rated Groceries with at least 20 reviews                     | Read all 8,000 documents (`COLLSCAN`)                 | Read 23 index keys and 10 documents, with no sort |
| **Q3** The 10 newest reviews of one product (product 3855, which has 299)       | Read all 67,544 reviews (`COLLSCAN`)                  | Read 10 index keys and 10 documents, with no sort |

Without an index, MongoDB reads every document and throws most of them away. With the right index it goes straight to the few it needs. For Q2 the number to check is **documents examined against documents returned**: 10 and 10, so the index does enough.

### The Q1 index decision

Query 1 has two range conditions (RAM of 8 or more, and price up to ₦300,000), so I tested two index orders (`plans/mongo_q1_index_comparison.txt`):

|                 | Order A: category, price, RAM | Order B: category, RAM, price |
| --------------- | ----------------------------- | ----------------------------- |
| Index keys read | 600                           | **267**                 |
| Sort in memory  | no                            | yes (about 265 entries)       |

I **kept B and dropped A**. B reads far fewer index entries, its in-memory sort is tiny, and every extra index slows every product insert and update. The usual "Equality, Sort, Range" rule suggested A, so this shows the rule is a guideline and not a law.

## Price sync demo

PostgreSQL is the source of truth for price. MongoDB holds a **copy** (`price_ngn`) so that "phones under ₦300,000" can be answered in one query. When a price changes in PostgreSQL, a small script copies it across. The demo shows the whole story for product 2 ("Ofada Rice 5kg Mini"):

1. **Before:** PostgreSQL and MongoDB both show ₦15,850.
2. **Change** the price in PostgreSQL (`UPDATE products SET price = 16900 WHERE product_id = 2;`).
3. **The gap:** PostgreSQL says 16,900, MongoDB still says 15,850. This is the short delay I described in `design.md`.
4. **Sync:** `export_prices.sql` writes the current PostgreSQL prices to `data/prices_now.json`, then `sync_prices.js` compares every price with the MongoDB copy and updates **only** the ones that differ (one `bulkWrite`).
5. **After:** MongoDB shows 16,900 and a new `price_synced_at`. Running the sync again changes nothing.

```
psql -U postgres -d ecommerce -At -f export_prices.sql -o data\prices_now.json
mongosh "mongodb://localhost:27017/naijamart" --file sync_prices.js
```

Until the sync runs, the website may show the old price while browsing. That is acceptable for browsing, but **checkout always reads the price from PostgreSQL**, so a customer is never charged a stale price.

## Trade-offs

- **Flexibility against rules.** MongoDB takes products with different fields easily, but it has no foreign keys. A review's `customer_id` points at a PostgreSQL customer, and MongoDB cannot check the customer exists. Keeping those links correct is the application's job.
- **A copy against one source.** Keeping a copy of the price (and name) in MongoDB makes searching fast, but the copy can be out of date until the sync runs. That is the BASE (eventual consistency) choice from section 6 of the case study. Orders and payments stay in PostgreSQL, which is the ACID choice, because a wrong balance is never acceptable.
- **Embed against reference.** Small things that stay small (specs) live inside the product. Things that can grow without limit (reviews) have their own collection, at the price of one extra read on the product page.
- **Indexes cost something.** They make reads fast but use disk and slow every write. That is why I kept only one of the two Q1 indexes.
- **More databases means more to run.** Three databases need backups, security and monitoring each, and any question that spans two of them is joined in the application.
- **The test database has no password.** That is fine for a local test. A real system would turn access control on.
- **The data is generated, not real.** Brands for non-phone products are made up, and the review text comes from a short list of phrases.

## Status

| Item                                            | Status                             |
| ----------------------------------------------- | ---------------------------------- |
| Design (`design.md`)                          | done                               |
| MongoDB data, indexes and before/after evidence | done                               |
| Price sync demo                                 | script written; screenshots to add |
| Redis cart demo with expiry                     | done`(redis_cart_demo.md)`       |
| Graph idea                                      | explained above, not built         |
