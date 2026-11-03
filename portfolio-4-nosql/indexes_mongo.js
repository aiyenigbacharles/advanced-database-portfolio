// indexes_mongo.js: creates the indexes for the three queries.
//   mongosh "mongodb://localhost:27017/naijamart" --file indexes_mongo.js
// Remove them again with drop_indexes_mongo.js.
//
// Field order follows the ESR rule as a starting point: Equality fields first, then the Sort field,
// then Range fields. Query 1 showed that the rule is only a guideline (see below).

// Q1 (phones, 8 GB or more RAM, up to 300,000 naira, cheapest first).
// It has TWO range conditions (ram and price), so I tested two index orders
// (the results are in plans/mongo_q1_index_comparison.txt):
//   A: parent_category, price_ngn, attributes.ram_gb   needs no sort, but examined 600 index keys
//   B: parent_category, attributes.ram_gb, price_ngn   examined 267 keys and sorts about 265 of them in memory
// DECISION: keep only B. It reads far fewer index entries, the in-memory sort is tiny, and every
// extra index slows down every product insert and update, so A is not worth its write cost.
db.products.createIndex({ parent_category: 1, 'attributes.ram_gb': 1, price_ngn: 1 },
                        { name: 'idx_q1_parent_ram_price' });

// Q2 (ten best-rated Groceries with at least 20 reviews):
// equality on parent_category, sort on rating_avg (high to low), range on rating_count
db.products.createIndex({ parent_category: 1, rating_avg: -1, rating_count: 1 },
                        { name: 'idx_q2_parent_rating_count' });

// Q3 (ten newest reviews of one product): equality on product_id, sort on created_at (newest first)
db.reviews.createIndex({ product_id: 1, created_at: -1 },
                       { name: 'idx_q3_product_newest' });

console.log('indexes on products: ' + db.products.getIndexes().map((i) => i.name).join(', '));
console.log('indexes on reviews:  ' + db.reviews.getIndexes().map((i) => i.name).join(', '));
