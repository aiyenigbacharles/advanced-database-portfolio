// drop_indexes_mongo.js: removes the indexes created by indexes_mongo.js (it keeps _id and product_id).
//   mongosh "mongodb://localhost:27017/naijamart" --file drop_indexes_mongo.js
const toDrop = [
  ['products', 'idx_q1_parent_ram_price'],
  ['products', 'idx_q2_parent_rating_count'],
  ['reviews',  'idx_q3_product_newest'],
  // The rejected Q1 index (order A). It only exists if it was created for the comparison,
  // so "not there" for this one is normal.
  ['products', 'idx_q1_parent_price_ram']
];
for (const [collection, name] of toDrop) {
  try {
    db.getCollection(collection).dropIndex(name);
    console.log('dropped ' + collection + '.' + name);
  } catch (e) {
    console.log('not there: ' + collection + '.' + name);
  }
}
