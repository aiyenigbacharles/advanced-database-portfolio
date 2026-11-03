-- export_products.sql: writes every product (with its category and parent category) as one JSON array.
-- seed_mongo.js reads this file to build the MongoDB product documents.
--   psql -U postgres -d ecommerce -At -f export_products.sql -o data\products_export.json
-- (-At = plain output without headers or borders; -o = write the result into that file.)
SELECT json_agg(json_build_object(
         'product_id',      p.product_id,
         'seller_id',       p.seller_id,
         'category',        c.name,
         'parent_category', COALESCE(pc.name, c.name),
         'name',            p.name,
         'description',     p.description,
         'price_ngn',       p.price)
       ORDER BY p.product_id)
FROM products p
JOIN categories c ON c.category_id = p.category_id
LEFT JOIN categories pc ON pc.category_id = c.parent_category_id;
