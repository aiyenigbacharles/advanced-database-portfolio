-- export_prices.sql: writes the CURRENT price of every product from PostgreSQL as a JSON file.
-- sync_prices.js reads this file and copies any changed price into MongoDB.
--   psql -U postgres -d ecommerce -At -f export_prices.sql -o data\prices_now.json
SELECT json_agg(json_build_object('product_id', product_id, 'price_ngn', price) ORDER BY product_id)
FROM products;
