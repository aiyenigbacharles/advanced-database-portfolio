function makeRandom(seed) {
  let a = seed;
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = makeRandom(42);
const pick = (list) => list[Math.floor(rand() * list.length)];

// ---------- small helpers ----------
const TODAY = Date.UTC(2026, 9, 15);                       // the fixed "today" of the seed data: 15 Oct 2026
const daysFromToday = (days) => new Date(TODAY + days * 86400000);

// pick between min and max different items from a list (kept in their original order)
function pickSome(list, min, max) {
  const n = min + Math.floor(rand() * (max - min + 1));
  const left = [...list];
  const chosen = [];
  while (chosen.length < n && left.length > 0) {
    chosen.push(left.splice(Math.floor(rand() * left.length), 1)[0]);
  }
  return list.filter((x) => chosen.includes(x));
}

const COLOURS = ['Black', 'White', 'Blue', 'Green', 'Red', 'Brown', 'Gold', 'Purple', 'Yellow'];

// Attributes for the three Phones sub-categories (Query 1 depends on these).
function phoneAttributes(p) {
  const price = Number(p.price_ngn);   // in case the price was exported as text such as "155000.00"

  if (p.category === 'Smartphones') {
    // RAM follows the price: cheap phones have less, expensive phones have more.
    let ram_gb;
    if (price < 130000)      ram_gb = pick([4, 6]);
    else if (price < 220000) ram_gb = pick([6, 8]);
    else if (price < 350000) ram_gb = pick([8, 12]);
    else                     ram_gb = pick([12, 16]);

    const attrs = {
      ram_gb,
      storage_gb: pick([64, 128, 256]),
      battery_mah: pick([4000, 5000, 6000]),
      screen_inches: pick([6.1, 6.5, 6.7]),
      network: pick(['4G', '5G']),
      dual_sim: pick([true, false])
    };

    // iPhone rule: the refurbished iPhone 11 models have 4 GB RAM and 4G only. The random
    // choices above are still drawn first and then overridden, so every other product's
    // data stays exactly the same.
    if (p.name.includes('iPhone')) {
      attrs.ram_gb = 4;
      attrs.network = '4G';
    }
    return attrs;
  }

  if (p.category === 'Tablets') {
    // Same kinds of fields as phones, with tablet-sized values (prices run about 60,000 to 260,000).
    let ram_gb;
    if (price < 100000)      ram_gb = pick([3, 4]);
    else if (price < 180000) ram_gb = pick([4, 6]);
    else                     ram_gb = pick([6, 8]);

    return {
      ram_gb,
      storage_gb: pick([32, 64, 128, 256]),
      battery_mah: pick([6000, 7000, 8000, 10000]),
      screen_inches: pick([8, 10.1, 10.4, 11]),
      network: pick(['Wi-Fi', '4G']),
      dual_sim: false
    };
  }

  // Phone Accessories: no RAM or storage.
  // "Fast Charger 33W Premium" has a wattage in its name; "Phone Case Lite" does not.
  // So only some accessories get a wattage field (documents can differ even inside one category).
  const watts = p.name.match(/(\d+)W/);
  const attrs = { compatible_with: pick(['Android', 'iPhone', 'Universal']) };
  if (watts) attrs.wattage = Number(watts[1]);
  return attrs;
}


// ---------- Fashion ----------
function fashionAttributes(p) {
  if (p.category === 'Ankara and Fabrics') {
    const yards = p.name.match(/(\d+)\s?Yards/i);          // "Ankara Fabric 6 Yards" -> 6
    const attrs = {
      fabric: p.name.includes('Aso Oke') ? 'Aso Oke' : p.name.includes('Lace') ? 'Lace' : 'Ankara',
      colours: pickSome(COLOURS, 1, 3)
    };
    if (yards) attrs.length_yards = Number(yards[1]);
    return attrs;
  }
  if (p.category === 'Shoes and Bags') {
    if (/bag|backpack/i.test(p.name)) {                       // bags have no sizes
      return { material: pick(['Leather', 'Canvas', 'Synthetic']), colours: pickSome(COLOURS, 1, 3) };
    }
    return {                                                  // shoes use numbers, not S/M/L
      sizes: pickSome([39, 40, 41, 42, 43, 44, 45], 3, 6),
      colours: pickSome(COLOURS, 1, 3),
      gender: pick(['Men', 'Women', 'Unisex'])
    };
  }
  // Mens Wear and Womens Wear
  return {
    sizes: pickSome(['S', 'M', 'L', 'XL', 'XXL'], 3, 5),
    colours: pickSome(COLOURS, 1, 3),
    fabric: pick(['Cotton', 'Linen', 'Polyester', 'Ankara']),
    gender: p.category === 'Mens Wear' ? 'Men' : 'Women'
  };
}

// ---------- Groceries ----------
function groceryAttributes(p) {
  const attrs = {};
  const kg = p.name.match(/(\d+(?:\.\d+)?)\s?kg/i);        // "Garri 5kg" -> 5
  const grams = p.name.match(/(\d+)\s?g\b/i);               // "Instant Coffee 200g" -> 0.2 kg
  const litres = p.name.match(/(\d+(?:\.\d+)?)\s?Litres?/i); // "Palm Oil 4 Litres" -> 4
  const packOf = p.name.match(/Pack of (\d+)/i);             // "Malt Drink Pack of 24" -> 24
  if (kg) attrs.weight_kg = Number(kg[1]);
  else if (grams) attrs.weight_kg = Number(grams[1]) / 1000;
  if (litres) attrs.volume_litres = Number(litres[1]);
  if (packOf) attrs.pack_count = Number(packOf[1]);
  attrs.best_before = daysFromToday(pick([180, 270, 365, 540, 730]));   // a real date
  attrs.origin = p.category === 'Rice and Grains'
    ? pick(['Ofada', 'Abakaliki', 'Kebbi', 'Imported'])
    : pick(['Nigeria', 'Nigeria', 'Imported']);
  return attrs;
}

// ---------- Home and Kitchen ----------
function homeAttributes(p) {
  const litres = p.name.match(/(\d+(?:\.\d+)?)\s?L\b/);      // "Pressure Cooker 6L" -> 6
  const cm = p.name.match(/(\d+)\s?cm/i);                    // "Frying Pan 28cm" -> 28
  if (p.category === 'Bedding') {
    return {
      bed_size: /King/i.test(p.name) ? 'King' : pick(['Single', 'Double', 'Queen', 'King']),
      material: pick(['Cotton', 'Polyester', 'Microfibre']),
      colours: pickSome(COLOURS, 1, 3)
    };
  }
  if (p.category === 'Cookware') {
    const attrs = { material: pick(['Aluminium', 'Stainless steel', 'Non-stick coated']) };
    if (litres) attrs.capacity_litres = Number(litres[1]);
    if (cm) attrs.diameter_cm = Number(cm[1]);
    return attrs;
  }
  if (p.category === 'Furniture') {
    return {
      material: pick(['Wood', 'Metal', 'Plastic']),
      colours: pickSome(COLOURS, 1, 2),
      assembly_required: pick([true, false])
    };
  }
  // Small Appliances
  const attrs = { power_watts: pick([600, 800, 1000, 1500, 1800]), warranty_months: pick([6, 12, 24]), voltage: '220-240V' };
  if (litres) attrs.capacity_litres = Number(litres[1]);
  return attrs;
}

// ---------- Beauty ----------
function beautyAttributes(p) {
  const ml = p.name.match(/(\d+)\s?ml/i);                    // "Oud Perfume 100ml" -> 100
  const grams = p.name.match(/(\d+)\s?g\b/i);               // "Black Soap 500g" -> 500
  const inches = p.name.match(/(\d+)\s?inch/i);              // "Human Hair Wig 14 inch" -> 14
  if (p.category === 'Fragrance') {
    return { volume_ml: ml ? Number(ml[1]) : pick([50, 100, 200]), gender: pick(['Men', 'Women', 'Unisex']) };
  }
  if (p.category === 'Hair Care') {
    const attrs = { hair_type: pick(['Natural', 'Relaxed', 'All hair types']) };
    if (inches) attrs.length_inches = Number(inches[1]);
    return attrs;
  }
  if (p.category === 'Makeup') {
    return { shade: pick(['Fair', 'Light', 'Medium', 'Tan', 'Deep']) };
  }
  // Skincare
  const attrs = { skin_type: pick(['Oily', 'Dry', 'Combination', 'All skin types']) };
  if (grams) attrs.weight_g = Number(grams[1]);
  return attrs;
}

// ---------- choose the right function for each product ----------
function attributesFor(p) {
  switch (p.parent_category) {
    case 'Phones':           return phoneAttributes(p);
    case 'Fashion':          return fashionAttributes(p);
    case 'Groceries':        return groceryAttributes(p);
    case 'Home and Kitchen': return homeAttributes(p);
    case 'Beauty':           return beautyAttributes(p);
    default: throw new Error('Unknown parent_category: ' + p.parent_category);
  }
}

// ---------- Step 4c: brand, long description, and the product document ----------
// Brand and description use their OWN random generators, so the attributes above
// stay exactly the same as before.
const randBrand = makeRandom(7);
const pickBrand = (list) => list[Math.floor(randBrand() * list.length)];

// PostgreSQL has no brand column, so the brand comes from the product name when there is one,
// and from a short list of made-up brands for everything else.
const KNOWN_BRANDS = [['Infinix', 'Infinix'], ['Tecno', 'Tecno'], ['Samsung', 'Samsung'],
                      ['Redmi', 'Xiaomi'], ['iPhone', 'Apple'], ['Lenovo', 'Lenovo']];
const MADE_UP_BRANDS = {
  'Phones':           ['VoltEdge', 'SoundNest', 'ChargePro', 'GripGuard'],
  'Fashion':          ['Ade Couture', 'Lagos Loom', 'Zuma Wears', 'Kente Line'],
  'Groceries':        ['Mama Naija', 'Golden Harvest', 'Sunrise Foods', 'Farmfresh'],
  'Home and Kitchen': ['HomeEase', 'Kitchen Kings', 'CozyNest', 'Lagos Living'],
  'Beauty':           ['Glow Naija', 'Shea Radiance', 'Zuri Beauty', 'Pure Ife']
};
function brandFor(p) {
  for (const [word, brand] of KNOWN_BRANDS) {
    if (p.name.includes(word)) return brand;
  }
  return pickBrand(MADE_UP_BRANDS[p.parent_category]);
}

// "ram_gb" -> "ram gb", dates -> 2027-10-15, lists -> "S, M, L"
function showValue(v) {
  if (v instanceof Date) return v.toISOString().slice(0, 10);
  if (Array.isArray(v)) return v.join(', ');
  return String(v);
}

// The LONG description (MongoDB is the source for this). PostgreSQL keeps only the short one.
function longDescription(p, brand, attributes) {
  const details = Object.entries(attributes)
    .map(([key, value]) => `${key.replace(/_/g, ' ')}: ${showValue(value)}`)
    .join('; ');
  // some products (about 1 in 5) have no short description in PostgreSQL, so allow for that
  const shortText = p.description ? p.description + ' ' : '';
  return `${p.name} by ${brand}. ${shortText}` +
         `Category: ${p.parent_category}, ${p.category}. Details: ${details}. ` +
         `Sold by NaijaMart seller ${p.seller_id}, with delivery across Nigeria.`;
}

// One MongoDB product document. Price and stock live in PostgreSQL (see design.md section 3).
function buildProduct(p, attributes) {
  const brand = brandFor(p);
  return {
    product_id: p.product_id,                 // the link to PostgreSQL products.product_id
    name: p.name,
    brand,
    description: longDescription(p, brand, attributes),
    category: p.category,
    parent_category: p.parent_category,
    seller_id: p.seller_id,                   // a link only
    attributes,
    price_ngn: Number(p.price_ngn),           // a COPY of the PostgreSQL price, for searching and display
    price_synced_at: new Date(TODAY),         // when the copy was last synced
    rating_avg: 0,                            // filled in from the reviews in the next step
    rating_count: 0
  };
}

// ---------- load the exported products and build every document ----------
const fs = require('fs');
const products = JSON.parse(fs.readFileSync('data/products_export.json', 'utf8'));
console.log('products loaded:', products.length);

// Go through the products in file order, so the same seed always gives the same data.
const docs = products.map((p) => buildProduct(p, attributesFor(p)));
console.log('documents built:', docs.length);

// ---------- Step 4d: reviews, and the rating summary on each product ----------
// Reviews use their OWN random generator, so products and attributes stay exactly the same.
const randReview = makeRandom(99);
const rnd = () => randReview();
const rpick = (list) => list[Math.floor(rnd() * list.length)];

const TITLES = {
  5: ['Excellent', 'Love it', 'Highly recommended'],
  4: ['Very good', 'Good value', 'Happy with it'],
  3: ['Okay', 'Average', 'Does the job'],
  2: ['Disappointing', 'Not great'],
  1: ['Terrible', 'Do not buy']
};
const COMMENTS = {
  5: ['Excellent quality, exactly as described.', 'Fast delivery and great value for money.',
      'Very happy with this purchase. Will buy again.', 'Works perfectly. Highly recommended.'],
  4: ['Good product, small issues with packaging.', 'Nice quality for the price.',
      'Arrived on time and works well.', 'Happy overall, would recommend.'],
  3: ['It is okay, nothing special.', 'Average quality for the price.',
      'Delivery was slow but the product is fine.'],
  2: ['Not as good as the pictures.', 'Quality is poor for the price.', 'Took too long to arrive.'],
  1: ['Very poor quality, I want a refund.', 'Arrived damaged.', 'Not what I ordered.']
};
const REVIEW_START = Date.UTC(2025, 0, 1);       // reviews are dated between 1 Jan 2025 and "today"

// How many reviews a product gets: most have few or none, about 1 in 100 is a "hit".
function reviewCountFor() {
  if (rnd() < 0.01) return 100 + Math.floor(rnd() * 200);
  return Math.floor(Math.pow(rnd(), 5) * 40);
}

const reviews = [];
for (const d of docs) {
  const count = reviewCountFor();
  const quality = 2.6 + rnd() * 2.3;             // how good this product is, from 2.6 to 4.9
  let total = 0;
  for (let i = 0; i < count; i++) {
    const noise = (rnd() + rnd() + rnd() - 1.5) * 1.2;     // a bit of variety around the quality
    const rating = Math.min(5, Math.max(1, Math.round(quality + noise)));
    total += rating;
    reviews.push({
      product_id: d.product_id,                                  // the link to the product
      customer_id: 1 + Math.floor(rnd() * 25000),                // the link to PostgreSQL customers
      rating,
      title: rpick(TITLES[rating]),
      comment: rpick(COMMENTS[rating]),
      helpful_votes: Math.floor(Math.pow(rnd(), 3) * 30),
      verified_purchase: rnd() < 0.8,
      created_at: new Date(REVIEW_START + Math.floor(rnd() * (TODAY - REVIEW_START)))
    });
  }
  // the summary stored on the product is worked out from the real reviews above
  d.rating_count = count;
  d.rating_avg = count > 0 ? Math.round((total / count) * 100) / 100 : null;
}

// ---------- checks ----------
console.log('reviews built:', reviews.length);
const counts = docs.map((d) => d.rating_count);
console.log('products with no reviews:', counts.filter((c) => c === 0).length);
console.log('products with 20 or more reviews:', counts.filter((c) => c >= 20).length);
console.log('most reviews on one product:', Math.max(...counts));

const spread = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
reviews.forEach((r) => spread[r.rating]++);
console.log('reviews per star rating:', spread);

const firstReviewed = docs.find((d) => d.rating_count > 0);
console.log('a product with its summary:', { product_id: firstReviewed.product_id, name: firstReviewed.name,
                                            rating_avg: firstReviewed.rating_avg, rating_count: firstReviewed.rating_count });
console.log('one of its reviews:', reviews.find((r) => r.product_id === firstReviewed.product_id));

// A preview of what Query 2 should return later: the best-rated Groceries with at least 20 reviews.
console.log('top 5 Groceries (20+ reviews):');
console.log(docs.filter((d) => d.parent_category === 'Groceries' && d.rating_count >= 20)
                .sort((a, b) => b.rating_avg - a.rating_avg)
                .slice(0, 5)
                .map((d) => `${d.rating_avg} (${d.rating_count} reviews) ${d.name}`));

// ---------- Step 4e: load everything into MongoDB ----------
// "db" is the naijamart database, because the script was started with mongodb://localhost:27017/naijamart
db.products.drop();      // start clean, so this script can be run again and again
db.reviews.drop();

// This index is the safety net: no two documents may have the same product_id,
// so a product cannot be loaded twice. (The indexes for the three queries come later,
// after we have measured how slow the queries are WITHOUT them.)
db.products.createIndex({ product_id: 1 }, { unique: true });

function insertInChunks(collection, items, size) {
  for (let i = 0; i < items.length; i += size) {
    collection.insertMany(items.slice(i, i + size));
  }
}
insertInChunks(db.products, docs, 2000);
insertInChunks(db.reviews, reviews, 10000);

// ---------- checks on what is now inside MongoDB ----------
console.log('--- inside MongoDB now ---');
console.log('products in MongoDB:', db.products.countDocuments());
console.log('reviews in MongoDB:', db.reviews.countDocuments());
console.log('products with 20 or more reviews:', db.products.countDocuments({ rating_count: { $gte: 20 } }));

// The rating_count on every product, added up, must equal the number of reviews.
console.log('sum of rating_count over all products:',
            db.products.aggregate([{ $group: { _id: null, total: { $sum: '$rating_count' } } }]).toArray()[0].total);

// The unique index in action: loading product 1 a second time must be refused.
try {
  db.products.insertOne({ product_id: 1, name: 'duplicate of product 1' });
  console.log('PROBLEM: the duplicate was accepted');
} catch (e) {
  console.log('duplicate product_id refused: error code', e.code, '-', String(e.message).split(' collection')[0]);
}

console.log('indexes on products:', db.products.getIndexes().map((ix) => ix.name));
console.log('one stored product:');
console.log(db.products.findOne({ product_id: 4 }));