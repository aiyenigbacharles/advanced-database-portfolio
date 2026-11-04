// sync_prices.js: copies changed prices from PostgreSQL into the MongoDB product documents.
//   1. psql -U postgres -d ecommerce -At -f export_prices.sql -o data\prices_now.json
//   2. mongosh "mongodb://localhost:27017/naijamart" --file sync_prices.js
// PostgreSQL is the source of truth. MongoDB only holds a COPY of each price (price_ngn), so this
// script compares the two and updates ONLY the products whose price is different.
const fs = require('fs');
const pgPrices = JSON.parse(fs.readFileSync('data/prices_now.json', 'utf8').replace(/^\uFEFF/, ''));

// the price copy MongoDB has now, as a lookup: product_id -> price_ngn
const mongoPrices = new Map(db.products.find({}, { product_id: 1, price_ngn: 1 }).toArray()
                                      .map((d) => [d.product_id, d.price_ngn]));

const changes = [];
let missing = 0;
for (const row of pgPrices) {
  const newPrice = Number(row.price_ngn);
  if (!mongoPrices.has(row.product_id)) { missing++; continue; }      // in PostgreSQL but not in MongoDB
  const oldPrice = mongoPrices.get(row.product_id);
  if (oldPrice !== newPrice) {
    changes.push({ product_id: row.product_id, oldPrice, newPrice });
  }
}

changes.slice(0, 10).forEach((c) => console.log(`product ${c.product_id}: ${c.oldPrice} -> ${c.newPrice}`));
if (changes.length > 10) console.log(`... and ${changes.length - 10} more`);

if (changes.length > 0) {
  db.products.bulkWrite(changes.map((c) => ({
    updateOne: {
      filter: { product_id: c.product_id },
      update: { $set: { price_ngn: c.newPrice, price_synced_at: new Date() } }   // when the copy was last updated
    }
  })));
}
console.log(`checked ${pgPrices.length} prices, changed ${changes.length}, not in MongoDB ${missing}`);
