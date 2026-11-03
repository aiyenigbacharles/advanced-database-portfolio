# Portfolio 4: NoSQL Design

**Case study:** NaijaMart. **Databases used here:** MongoDB (document model, database `naijamart`) and Redis (key-value).

My plan is to split the data by what it needs. **PostgreSQL** keeps everything involving money and stock (orders, payments, wallet, price, stock), because those need transactions. **MongoDB** keeps the **product catalogue** and the **reviews**, because their shape changes from product to product and they are mostly read, not used for money. **Redis** keeps the shopping cart, as the case study says (section 6), and I will build a small cart demo.

---

## 1. Catalogue fields

Each category has details that the others do not. These are the extra fields (name, brand, description and images are shared by all products, so they are not listed).

| Category | Extra fields only this category has |
|---|---|
| **Phones** (Smartphones, Tablets) | `ram_gb`, `storage_gb`, `battery_mah`, `screen_inches`, `network` (4G or 5G), `dual_sim` |
| **Fashion** (Womens Wear, Mens Wear and so on) | `sizes` (a list, for example S, M, L), `colours` (a list), `fabric`, `gender` |
| **Groceries** (Rice and Grains, Snacks and so on) | `weight_kg`, `best_before` (a date), `origin` (for example Ofada) |

**In one PostgreSQL table** I would need all 13 of these extra columns, and each product would fill only 3 to 6 of them. That leaves about 54% (phones) to 77% (groceries) of the extra columns empty (`NULL`) on every row. Every new category (say Furniture) would mean `ALTER TABLE` to add more columns. A list such as `sizes` does not fit one column either. The usual workaround, a key/value side table, makes a question like "RAM of 8 or more" slow, because every value is stored as text. In MongoDB each product document simply holds the fields it has, in a nested `attributes` block.

---

## 2. Embed or reference?

I will keep reviews in a **separate `reviews` collection**, and each review points to its product with `product_id`. The product document keeps only a small summary (`rating_avg` and `rating_count`).

If a popular phone got 50,000 reviews at about 300 bytes each, that is roughly 15 MB. One MongoDB document is limited to 16 MB, so the product would nearly burst. Even before that, every product page would load all 50,000 reviews, and every new review would rewrite that giant document. A separate collection lets me load 10 reviews at a time, using an index on `product_id` and date. The price I pay is that a product page needs two reads (the product, then its first reviews), which is fine.

My rule: **embed** small things that belong to one product and stay small (specs, image list). **Reference** things that can grow without limit (reviews).

---

## 3. Source of truth

**PostgreSQL is the source of truth for price, stock, seller, category and whether a product is active**, because those involve money and must be exact.

| Stored in MongoDB (product document) | Stays in PostgreSQL (the source of truth) |
|---|---|
| `product_id` (the link, same number as `products.product_id`, with a unique index) | stock quantity |
| the full description (**MongoDB is the source**), images | the real price used for orders |
| name and brand (name is a copy) | `name` (**PostgreSQL is the source**) and a short copy of the description |
| category and parent category (for example Smartphones under Phones) | seller details and bank account |
| `seller_id` (a link only) | orders, payments, wallet |
| the `attributes` block (RAM, sizes, weight and so on) | |
| `rating_avg`, `rating_count` | |
| `price_ngn`, a **copy** of the price, used only for searching and display | |

**Description and name exist in both databases.** The `description` is written in MongoDB, which is the source for the long version. The PostgreSQL `products.description` column keeps a short copy (support staff and order screens use it), and if the two ever differ, MongoDB is right. The `name` works the other way: PostgreSQL is the source (it appears on orders and receipts), and the MongoDB name is a copy that the same sync keeps up to date.

**If the price changes,** the change is made in **PostgreSQL first**. A small script then copies the new price into the MongoDB document. Until it runs, browsing might show the old price for a short time, which is acceptable for browsing. But **checkout always reads the price from PostgreSQL** (that is where `order_items.unit_price` comes from), so a customer is never charged a stale price. If the price differs from what they saw, they are shown the new one before paying.

**I will demonstrate this sync, not just describe it:**
1. Show product X: its price in PostgreSQL and its `price_ngn` in MongoDB (they match).
2. Change the price in PostgreSQL with one `UPDATE`.
3. Show MongoDB again: it still has the **old** price. This is the short gap I described.
4. Run the sync script (it compares each product's PostgreSQL price with the MongoDB copy and updates only the ones that differ).
5. Show MongoDB a third time: `price_ngn` now has the **new** price, and `price_synced_at` has changed.

Screenshots of steps 1, 3 and 5 will show the before, the gap and the after.

---

## 4. Queries that must be fast

| # | Question | Who asks | Collection and how it is answered | Index I plan (in order) |
|---|---|---|---|---|
| 1 | "Phones with at least 8 GB RAM under ₦300,000" | A customer searching | `products`: parent category is Phones, `attributes.ram_gb` is 8 or more, `price_ngn` is 300,000 or less, cheapest first | `parent_category`, `price_ngn`, `attributes.ram_gb` |
| 2 | "The 10 best-rated products in Groceries" | A manager, or the homepage | `products`: parent category is Groceries, at least 20 reviews (so a product with one 5-star review does not win), highest `rating_avg` first, 10 results | `parent_category`, `rating_avg` (high to low), `rating_count` |
| 3 | "The 10 newest reviews for product 1234" | A customer on a product page | `reviews`: `product_id` is 1234, newest first, 10 results | `product_id`, `created_at` (newest first) |

**How I ordered the index fields: Equality, Sort, Range (ESR).** Put the fields tested with `=` first (Equality), then the field the results are sorted by (Sort), then the fields tested with `>=` or `<=` (Range). That way MongoDB jumps straight to the right group, reads it already in the right order, and only then has to check the range. I treat the index plans above as a first guess to be tested, not a final answer.

- **Query 1 is the hard one.** It has two range conditions (`ram_gb >= 8` and `price_ngn <= 300000`), and an index can only be tight on one range at a time. My first index is tight on price and sorted by price, but it still has to look at every phone under ₦300,000 and check its RAM. I will test it with `explain("executionStats")` against the other order (`parent_category`, `attributes.ram_gb`, `price_ngn`), and compare how many index entries each one reads and whether MongoDB has to sort in memory. What I find goes into the performance analysis. **Result:** I tested both orders (`plans/mongo_q1_index_comparison.txt`) and kept the second one, `parent_category`, `attributes.ram_gb`, `price_ngn`, because it reads far fewer index entries. The ESR order was only a first guess.
- **Query 2 filters and sorts.** It sorts by `rating_avg` but also filters `rating_count >= 20`. When I run it I will compare **documents examined** with **documents returned** (`totalDocsExamined` against `nReturned`). If examined is far bigger than the 10 returned, the index is not doing enough and I will change it.
- **Query 3 is the simple case.** Equality on `product_id` and sort by date. It is also the reason reviews live in their own collection: it only works well if reviews can be found by `product_id` on their own.

---

## 5. Shopping cart in Redis (small demo)

The cart changes with every tap, must load instantly, and does not need to last forever, which is exactly what a key-value store is for. Each customer's cart will be one Redis key, `cart:<customer_id>`, holding a **hash** of `product_id` to quantity. The cart gets an **expiry time**: in real use it would expire about 7 days after the last change, and in the demo I will use 60 seconds so the expiry can be seen. The cart stores only product ids and quantities, never prices, because the price is read from PostgreSQL at checkout. The cart also lives on the server, not in the phone, so a dropped mobile connection does not lose it, which matters given the patchy internet in the case study.
