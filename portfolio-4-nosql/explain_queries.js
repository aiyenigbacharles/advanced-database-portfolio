// explain_queries.js: runs the three Portfolio 4 queries with explain("executionStats").
//
//   BEFORE the indexes:  mongosh "mongodb://localhost:27017/naijamart" --file explain_queries.js
//   AFTER  the indexes:  the same command, once indexes_mongo.js has been run.
//
// For each query it prints how MongoDB answered it and how much work it did:
//   plan             the steps MongoDB used, outermost first.
//                    COLLSCAN = read every document. IXSCAN = used an index. SORT = sorted in memory.
//   returned         how many documents the query gave back
//   keys examined    how many index entries were read (0 when there is no index)
//   docs examined    how many documents were read. If this is far bigger than "returned",
//                    MongoDB is doing a lot of work that it throws away.
//   median ms        each query is run 3 times and the middle time is kept (as in Portfolio 2)

const HIT_PRODUCT = 3855;   // "Beans 10kg Classic", the product with the most reviews (299)

// The plan steps from the outside in, for example "LIMIT > FETCH > IXSCAN [index name]"
function planChain(explained) {
  let node = explained.queryPlanner.winningPlan;
  if (node.queryPlan) node = node.queryPlan;            // newer MongoDB versions wrap the plan
  const steps = [];
  while (node) {
    steps.push(node.stage + (node.indexName ? ' [' + node.indexName + ']' : ''));
    node = node.inputStage || (node.inputStages ? node.inputStages[0] : null);
  }
  return steps.join(' > ');
}

function middle(numbers) {
  return [...numbers].sort((a, b) => a - b)[1];
}

// makeCursor must build a NEW cursor each time, because a cursor can only be used once.
function measure(label, makeCursor) {
  const times = [];
  let last;
  for (let i = 0; i < 3; i++) {
    last = makeCursor().explain('executionStats');
    times.push(last.executionStats.executionTimeMillis);
  }
  const stats = last.executionStats;
  const chain = planChain(last);
  console.log(label);
  console.log('  plan:          ' + chain);
  console.log('  returned:      ' + stats.nReturned);
  console.log('  keys examined: ' + stats.totalKeysExamined);
  console.log('  docs examined: ' + stats.totalDocsExamined);
  console.log('  time ms:       ' + times.join(', ') + '   (median ' + middle(times) + ')');
  console.log('  sorted in memory: ' + (chain.includes('SORT') ? 'YES' : 'no'));
  console.log('');
}

const q1 = () => db.products
  .find({ parent_category: 'Phones', price_ngn: { $lte: 300000 }, 'attributes.ram_gb': { $gte: 8 } })
  .sort({ price_ngn: 1 })
  .limit(20);                                            // the first page of results, cheapest first

const q2 = () => db.products
  .find({ parent_category: 'Groceries', rating_count: { $gte: 20 } })
  .sort({ rating_avg: -1 })
  .limit(10);

const q3 = () => db.reviews
  .find({ product_id: HIT_PRODUCT })
  .sort({ created_at: -1 })
  .limit(10);

console.log('=== Portfolio 4: explain results ===');
console.log('indexes on products: ' + db.products.getIndexes().map((i) => i.name).join(', '));
console.log('indexes on reviews:  ' + db.reviews.getIndexes().map((i) => i.name).join(', '));
console.log('');

measure('Q1 Phones with 8 GB RAM or more, up to 300,000 naira, cheapest first (first 20)  [MongoDB chooses]', q1);
measure('Q2 Ten best-rated Groceries with at least 20 reviews  [MongoDB chooses]', q2);
measure('Q3 Ten newest reviews of product ' + HIT_PRODUCT + '  [MongoDB chooses]', q3);

// If the two Query 1 indexes exist, compare them directly by forcing each one with hint().
const names = db.products.getIndexes().map((i) => i.name);
if (names.includes('idx_q1_parent_price_ram')) {
  measure('Q1 forced to use idx_q1_parent_price_ram  (parent_category, price_ngn, attributes.ram_gb)',
          () => q1().hint('idx_q1_parent_price_ram'));
}
if (names.includes('idx_q1_parent_ram_price')) {
  measure('Q1 forced to use idx_q1_parent_ram_price  (parent_category, attributes.ram_gb, price_ngn)',
          () => q1().hint('idx_q1_parent_ram_price'));
}
