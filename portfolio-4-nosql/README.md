
# Portfolio 4: NoSQL and Advanced Data Models

This portfolio adds two NoSQL databases to the NaijaMart case study. **MongoDB** (a document database) holds the product catalogue and the reviews, which are the data that does not fit neatly into tables. **Redis** (a key-value store) will hold the shopping cart. Everything involving money (orders, payments, wallet, price, stock) stays in **PostgreSQL**, because it needs transactions.

Start with `design.md`. It explains every decision in plain words.

## What goes where

| Data                                                    | Database            | Why                                                                                                                  |
| ------------------------------------------------------- | ------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Orders, payments, wallet, price, stock                  | PostgreSQL          | Money must be exact, and these follow ACID rules                                                                     |
| Product catalogue (with different details per category) | MongoDB (documents) | A phone has RAM and storage, a dress has sizes and colours, rice has weight. One table would be mostly empty columns |
| Product reviews                                         | MongoDB (documents) | They can grow without limit, so they live in their own collection                                                    |
| Shopping cart                                           | Redis (key-value)   | It changes with every tap and must load instantly                                                                    |

## The files in this folder

| File                          | What it is                                                                                             |
| ----------------------------- | ------------------------------------------------------------------------------------------------------ |
| `design.md`                 | The design: catalogue fields, embed or reference, source of truth, the three queries that must be fast |
| `export_products.sql`       | Exports the 8,000 products from PostgreSQL into `data/products_export.json`                          |
| `data/products_export.json` | The exported products (the input for the seed script)                                                  |
| `seed_mongo.js`             | Builds the product documents and the reviews, and loads them into MongoDB                              |
| `explain_queries.js`        | Runs the three queries with `explain` and prints how much work MongoDB did                           |
| `indexes_mongo.js`          | Creates the indexes for the three queries                                                              |
| `drop_indexes_mongo.js`     | Removes those indexes, so you can repeat the before and after                                          |
| `plans/`                    | Saved results: `mongo_before.txt`, `mongo_after.txt` and `mongo_q1_index_comparison.txt`         |
| `screenshots/`              | Screenshots of the work                                                                                |

## What the seed script builds

- **8,000 product documents**, one per PostgreSQL product. Each has a `product_id` that links it to PostgreSQL, a brand, a long description, the category and parent category, an `attributes` block with the fields only that kind of product has (for example `ram_gb` for phones or `sizes` for clothes), a copy of the price, and a rating summary.
- **67,544 reviews** in their own collection, each pointing to a product with `product_id`. About 1,091 products have 20 or more reviews, and some have none.
- The data is **repeatable**: the same seed always gives the same data, so your numbers match mine.

## How to run it

You need PostgreSQL (with the `ecommerce` database from Portfolios 1 and 2) and MongoDB with `mongosh`. I used MongoDB 9.0.4 and mongosh 2.13.0 on Windows. Open PowerShell in this folder.

**1. Export the products from PostgreSQL** (skip this if `data/products_export.json` is already there):

```
psql -U postgres -d ecommerce -At -f export_products.sql -o data\products_export.json
```

**2. Load MongoDB.** This drops and recreates the `products` and `reviews` collections in `naijamart`, so you can run it as often as you like:

```
mongosh "mongodb://localhost:27017/naijamart" --file seed_mongo.js
```

It should end with 8000 products, 67544 reviews, and a refused duplicate `product_id`.

**3. BEFORE: measure the queries with no indexes:**

```
mongosh "mongodb://localhost:27017/naijamart" --file explain_queries.js | Out-File -Encoding utf8 plans\mongo_before.txt
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

Each query is run 3 times and the middle time is kept. The times vary a little from run to run, so the table uses the steadier numbers: how many index entries (**keys**) and documents MongoDB had to read. The times are in the files in `plans/`.

| Query                                                                                 | Before (no index)                                       | After (with index)                                |
| ------------------------------------------------------------------------------------- | ------------------------------------------------------- | ------------------------------------------------- |
| **Q1** Phones with 8 GB RAM or more, up to ₦300,000, cheapest first (first 20) | Read all 8,000 documents (`COLLSCAN`) and sorted them | Read about 267 index keys and only 20 documents   |
| **Q2** The 10 best-rated Groceries with at least 20 reviews                     | Read all 8,000 documents                                | Read 23 index keys and 10 documents, with no sort |
| **Q3** The 10 newest reviews of one product                                     | Read all 67,544 reviews                                 | Read 10 index keys and 10 documents, with no sort |

In plain words: without an index, MongoDB reads every document and throws most of them away. With the right index it goes straight to the few it needs.

### The Q1 index decision

Query 1 has two range conditions (RAM of 8 or more, and price up to ₦300,000), so I tested two index orders (`plans/mongo_q1_index_comparison.txt`):

|                 | Order A: category, price, RAM | Order B: category, RAM, price |
| --------------- | ----------------------------- | ----------------------------- |
| Index keys read | 600                           | **267**                 |
| Sort in memory  | no                            | yes (about 265 entries)       |

I **kept B and dropped A**. B reads far fewer index entries, its in-memory sort is tiny, and every extra index slows every product insert and update. The usual "Equality, Sort, Range" rule suggested A, so this shows the rule is a guideline and not a law.

## Things worth knowing

- **No foreign keys in MongoDB.** A review's `customer_id` points at a PostgreSQL customer, but MongoDB cannot check that the customer exists. Keeping that link correct is the application's job. This is a real trade-off of splitting data across databases.
- **The price in MongoDB is a copy.** PostgreSQL is the source of truth, and checkout always reads the price from PostgreSQL. The copy is only for searching and display (see `design.md`, section 3).
- **Reviews are not stored inside the product** because a popular product could get tens of thousands of them, and one MongoDB document is limited to 16 MB.
- **The test database has no password.** That is fine for a local test, and a real system would turn access control on.
- **The data is generated, not real.** Brands for non-phone products are made up, and review text comes from a short list of phrases.

## Still to come

| Item                                                                                                | Status       |
| --------------------------------------------------------------------------------------------------- | ------------ |
| Price sync demo: change a price in PostgreSQL, then show the MongoDB copy updated by a small script | not done yet |
| Redis shopping cart with an expiry time                                                             | not done yet |
| Analysis: why MongoDB suits this data, and the findings above in full                               | not done yet |
