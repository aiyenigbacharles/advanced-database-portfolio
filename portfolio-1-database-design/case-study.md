# Case Study: NaijaMart

**Course:** MIT 8103 Advanced Database Systems
**Type:** Simulated organisation (a realistic business scenario)

NaijaMart is a made-up company. It is designed to behave like a real Nigerian online marketplace, so the data, problems and operations below reflect how such a business actually runs.

---

## 1. The Organisation

**Name:** NaijaMart Limited
**Head office:** Lagos, with regional hubs in Abuja and Port Harcourt
**Business type:** Online marketplace where independent Nigerian sellers list products and customers buy them through a website and mobile app

NaijaMart does not keep its own goods in one big warehouse. Most sellers store their own stock, and NaijaMart handles the shop front, payments, and delivery coordination. It earns a commission on every sale (7% on most items, 10% on fashion and beauty).

A few things make NaijaMart different from a textbook online shop:

- **Many sellers, one platform.** An order with three items can come from three different sellers in three different cities.
- **Mixed payment methods.** Customers pay by card, bank transfer, USSD, or Pay on Delivery. Pay on Delivery orders are paid in cash to the rider, so payment is confirmed days after the order.
- **Patchy internet.** Many customers shop on mobile data that drops often. The system must not lose a cart or double charge when a connection breaks.
- **Big sale spikes.** Normal days see about 3,000 orders. On Black Friday and in the December "Detty December" sale, it can jump to 40,000 orders in a day, with thousands of people chasing the same limited items.

---

## 2. The Users of the Database

| User | What they do with the data |
|---|---|
| **Customers** | Browse products, fill carts, place orders, pay, track delivery, leave reviews |
| **Sellers** | List products, set prices, update stock, see their orders and earnings |
| **Delivery riders and partner couriers** | Receive pickup and drop-off tasks, update delivery status |
| **Customer support staff** | Look up orders, handle refunds, resolve complaints |
| **Finance team** | Check payments, calculate seller payouts and commission, audit totals |
| **Operations managers** | Watch stock levels, delivery delays, and regional performance |
| **Data and marketing team** | Study buying patterns and build product recommendations |

---

## 3. The Major Data to Be Stored

### Core business data (structured, needs strict accuracy)

| Data | Examples of what is stored |
|---|---|
| **Customers** | Name, email, phone number, registration date, wallet balance |
| **Addresses** | Street, city, state (for example Lagos, FCT Abuja, Rivers), landmark, customer link |
| **Sellers** | Business name, owner, state, bank account for payouts, rating, approval status |
| **Categories** | Phones, Fashion, Groceries, Home and Kitchen, Beauty, and sub-categories |
| **Products** | Name, description, price in naira, seller, category, stock quantity |
| **Orders** | Customer, order date, delivery address, total amount, order status |
| **Order items** | Which product, how many, price at the time of purchase |
| **Payments** | Order, method (card, transfer, USSD, Pay on Delivery), amount, status, reference number |
| **Deliveries** | Order, rider or courier, pickup time, delivery time, status, failed attempt reason |
| **Reviews** | Customer, product, star rating, comment, date |

### Flexible and fast-changing data (suited to NoSQL)

| Data | Why it does not fit neatly into tables |
|---|---|
| **Product details** | A phone has RAM, storage and battery. A dress has size, colour and fabric. Rice has weight and brand. Each category has different fields. |
| **Shopping carts and sessions** | They change every few seconds and must load instantly. |
| **Product views and search logs** | Millions of small records that need very fast writes. |
| **"Bought together" links** | Customers connect to products, and products connect to other products. |

### Example order

> Amaka in Abuja orders a Tecno phone from a seller in Lagos and a bag of ofada rice from a seller in Ibadan. She pays 85,000 naira by card. The order is split into two deliveries. The phone arrives in two days. The rice delivery fails once because nobody answered the phone, then succeeds the next day.

This one example touches customers, sellers, products, orders, order items, payments and deliveries, which is why NaijaMart suits every part of the portfolio.

---

## 4. Key Operations the Database Supports

### Everyday operations

1. Register a customer and save their addresses
2. Onboard a seller and approve their account
3. Add a product and set its price and stock
4. Search products by name, category, price range or seller location
5. Add items to a cart
6. Place an order and reduce stock
7. Take payment and record the result
8. Assign a rider and update delivery status
9. Cancel an order and return the stock
10. Refund a failed or returned order to the customer's wallet
11. Post a product review and recalculate the product rating

### Reports and analysis

1. Total sales per state per month
2. Top 10 best selling products this week
3. Sellers with the highest returns or lowest ratings
4. Orders stuck in "pending" for more than 48 hours
5. Seller payout: sales minus the NaijaMart commission
6. Delivery success rate by city
7. Customers who bought a phone and later bought accessories

---

## 5. Real Problems NaijaMart Must Solve

These problems link directly to the course topics and will be used in the portfolio.

| Problem | What goes wrong | Course topic |
|---|---|---|
| **Messy duplicate data** | If seller details are copied onto every product row, one address change means editing thousands of rows | Normalisation, keys, constraints (Portfolio 1) |
| **Slow reports** | The "sales per state per month" report takes too long once there are hundreds of thousands of orders | Query optimisation, indexes, execution plans (Portfolio 2) |
| **The last item problem** | Two customers click "Buy" on the last phone at the same time, and both orders go through | Isolation and concurrency (Portfolio 3) |
| **Money taken, order not saved** | Payment succeeds but the server crashes before the order is recorded | Atomicity, commit and rollback (Portfolio 3) |
| **Products with different fields** | A single products table would be full of empty columns | Document model (Portfolio 4) |
| **Slow carts** | Loading a cart from the main database on every tap is too slow during a sale | Key-value store (Portfolio 4) |
| **Slow response across Nigeria** | A customer in Port Harcourt waits too long if every request goes to Lagos | Replication, sharding (Portfolio 5) |
| **Server or network failure** | If the Lagos server goes down, the whole platform stops | Availability, CAP theorem (Portfolio 5) |

---

## 6. Where Each Part of the System Sits

NaijaMart uses the right tool for each job instead of one database for everything.

| Part of NaijaMart | Database type | Reason |
|---|---|---|
| Orders, payments, sellers, customers | Relational (PostgreSQL) | Money must be exact, and records follow ACID rules |
| Product catalogue with varied details | Document (MongoDB) | Each category has different fields and the structure changes often |
| Carts and login sessions | Key-value (Redis) | Very fast reads and writes |
| "Customers also bought" suggestions | Graph (idea, explained in the write-up) | Based on relationships between customers and products |
| Regional copies of the data | Distributed setup | Faster access and survival of failures |

**Consistency choices:**

- **Strong consistency (ACID):** orders, payments, stock, wallet balances. A wrong balance is never acceptable.
- **Eventual consistency (BASE):** product views, ratings shown on the page, recommendations. Being a few seconds late is fine.

---

## 7. Scale Assumed for the Project

These figures are for the simulated data used in testing. They are small enough to run on a laptop but large enough to show real differences in query speed.

| Item | Test volume |
|---|---|
| Customers | 25,000 |
| Sellers | 500 |
| Products | 8,000 |
| Orders | 100,000 |
| Order items | about 250,000 |
| Payments | 100,000 |

The seed data uses Nigerian names, cities, naira prices and local payment methods so it looks like a real marketplace.

---

## 8. Data Protection and Rules

- NaijaMart handles personal data (names, phone numbers, addresses), so it must follow the **Nigeria Data Protection Act (NDPA)**.
- Card numbers are never stored in the database. Only the payment reference from the payment provider is kept.
- Staff see only what their job needs. For example, riders see a delivery address but not the customer's payment details (role based access).
- Financial records are kept and never deleted, only marked as cancelled or refunded.

---

## 9. Quick Summary (for the portfolio front page)

**NaijaMart** is a simulated Nigerian online marketplace connecting independent sellers to customers across the country. Its database stores customers, sellers, products, orders, payments and deliveries. It supports browsing, ordering, payment, delivery tracking, refunds and sales reporting. Its main challenges are heavy sale day traffic, products with very different details, stock that must never be oversold, and customers spread across a large country with unreliable internet. These challenges are used to demonstrate database design, query optimisation, transactions, NoSQL modelling, and distributed database setup in the five portfolio activities.
