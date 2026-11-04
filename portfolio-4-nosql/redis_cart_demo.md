# Redis shopping cart demo

**Case study:** NaijaMart. **Database:** Redis (key-value), run on Windows with Memurai. **Customer used:** 25001 (the demo shopper from Portfolio 3).

## Why the cart is in Redis

On NaijaMart a cart changes with almost every tap: add a phone case, change the quantity, remove a charger. During a big sale such as "Detty December" thousands of people do this at the same moment. Asking PostgreSQL to save and reload a cart on every tap would waste its time, because a cart is not money and does not need ACID guarantees. A cart only needs to be quick, and it should disappear by itself when the customer never comes back. That is what Redis is for. Redis keeps its data in memory, so reads and writes take a fraction of a millisecond.

Prices are **not** kept in the cart. The cart only says "product 3855, quantity 3". The price is read from PostgreSQL when the customer checks out, so a stale price in the cart can never be charged.

## How the cart is stored

One Redis key per customer: `cart:<customer_id>`. The value is a **hash**, which is a small table inside one key. Each field is a product id and each value is the quantity.

```
key  cart:25001
      3855  ->  3
         1  ->  1
       100  ->  1
```

## What I ran, and what it showed

I started the Redis shell with `memurai-cli` and ran the commands one at a time.

### 1. Check Redis is running

```
memurai-cli ping
PONG
```

`PONG` means the server is up. Screenshot: `screenshots/p4-redis-connected.png`

### 2. Create the cart

```
HSET cart:25001 3855 2 1 1
(integer) 2
```

This put two products in the cart: product 3855 (quantity 2) and product 1 (quantity 1). Redis answered `2` because two new fields were added.

### 3. Read the cart back

```
HGETALL cart:25001
1) "3855"
2) "2"
3) "1"
4) "1"
```

`HGETALL` returns the fields and values in pairs: 3855 is 2, and 1 is 1.

### 4. Change a quantity and add another item

```
HINCRBY cart:25001 3855 1
(integer) 3
HSET cart:25001 100 1
(integer) 1
HGETALL cart:25001
1) "3855"
2) "3"
3) "1"
4) "1"
5) "100"
6) "1"
```

`HINCRBY` added 1 to the quantity of product 3855, so it went from 2 to 3. `HSET` added product 100 as a new field. The cart now holds three products.

### 5. Give the cart an expiry time

```
EXPIRE cart:25001 60
(integer) 1
TTL cart:25001
(integer) 29
```

`EXPIRE` told Redis to delete the whole cart after 60 seconds. `TTL` (time to live) shows how many seconds are left; here it showed 29 a moment later. Screenshot: `screenshots/p4-redis-cart.png`

In real use the expiry would be about 7 days. I used 60 seconds only so that I could watch it happen.

### 6. The cart deletes itself

After waiting for the time to run out:

```
TTL cart:25001
(integer) -2
EXISTS cart:25001
(integer) 0
```

`-2` means "this key does not exist any more", and `EXISTS` returned `0`. Nobody deleted the cart; Redis removed it. Screenshot: `screenshots/p4-redis-expired.png`

## My answers

**Why a hash, and not the whole cart as one piece of text?**
If the cart were stored as one text value, such as `"3855:2,1:1"`, then changing one quantity would mean reading the whole text, editing it in my own code and writing all of it back. With a hash, I change one field directly. `HINCRBY` adds 1 to a single quantity inside Redis itself. If a customer on a bad connection taps "+" twice and both requests arrive together, Redis still applies both, one after the other, and no tap is lost.

**Why does the cart hold only product ids and quantities, never prices?**
The price belongs to PostgreSQL, which is the source of truth for money (see `design.md`, section 3). A cart can sit for days. If a seller lowers or raises a price in that time, a price saved in the cart would be wrong. By storing only the quantity, checkout always reads the current price from PostgreSQL, and that same price is saved into `order_items.unit_price`.

**What happens to the cart if the phone loses signal halfway through shopping?**
Nothing is lost. The cart lives on the server in Redis, not on the phone. When the phone reconnects, even on a different device, it asks for `cart:<customer_id>` and gets the same cart back, until the expiry time.

## Limits I'm honest about

- **The expiry is for the whole cart, not for single items.** Adding an item with `HSET` does **not** restart the countdown. A real shop would run `EXPIRE` again after every change, so that a cart that is still being used does not vanish. In this demo I did not do that.
- **Redis is not safe for money.** If Redis restarts, carts can be lost, depending on how it saves data to disk. That is acceptable for a cart and not acceptable for orders or payments, which stay in PostgreSQL.
- **Redis cannot check anything.** It does not know whether product 100 exists or is in stock. The checkout step has to check that against PostgreSQL.
