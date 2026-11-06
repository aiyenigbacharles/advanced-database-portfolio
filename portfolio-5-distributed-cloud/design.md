# Portfolio 5: Distributed and cloud design for NaijaMart

**Case study:** NaijaMart, a Nigerian online marketplace. **Built and tested:** a 3-node MongoDB replica set on my own PC (failover and CAP demos). **Discussed only (not built):** sharding, PostgreSQL replication, cloud hosting.

## 1. Why NaijaMart needs more than one copy of its data

NaijaMart has shoppers in Lagos, Abuja and Port Harcourt. During a sale such as "Detty December" the catalogue is read thousands of times a minute. Two things can go wrong with a single database server:

- **The server fails.** If the one machine holding the product catalogue crashes, nobody can browse or buy until it is repaired.
- **The server is overloaded.** One machine can only answer so many searches at once.

Replication (keeping copies) answers the first problem. Sharding (splitting the data) answers the second.

## 2. What I built: a 3-node replica set

A replica set is a group of MongoDB servers holding the same data. One is the **primary** and takes all writes. The others are **secondaries** and copy every change from the primary. I ran three `mongod` processes on one PC (ports 27018, 27019, 27020), set `naijamartRS`, and loaded the same `products` (8,000) and `reviews` (67,544) data from Portfolio 4.

This is a local simulation. On one PC, all three nodes share one power supply and one disk system, so it shows how the software behaves and not real protection against a hardware failure. In production the nodes would sit in separate places.

### 2.1 Copies are real
Connected directly to a secondary (27020), I counted 8,000 products and 67,544 reviews, the same as the primary. A write made on the primary appeared on the secondary. A write sent to the secondary was refused. Evidence: `screenshots/p5-secondary-has-data.png`, `p5-write-replicates.png`, `p5-secondary-refuses-write.png`.

### 2.2 Failover (one node lost)
| Step | What I saw |
|---|---|
| Before | 27018 was `PRIMARY`; 27019 and 27020 were `SECONDARY`, all `health=1` |
| I stopped 27018 (Ctrl+C) | 27018 showed `health=0`; **27019 became `PRIMARY` by itself**; 27020 stayed `SECONDARY` |
| Write during the outage | `updateOne` on product 1 returned `acknowledged: true` |
| I restarted 27018 | It rejoined as `SECONDARY`, and `findOne` on it showed the field written while it was off |

The two surviving nodes held an election because they were still a majority (2 of 3). Writing to the new primary worked, and the returning node copied what it had missed. Evidence: `p5-failover-before.png`, `p5-failover-after.png`, `p5-write-during-outage.png`, `p5-node-rejoined.png`, `p5-node-caught-up.png`.

### 2.3 CAP demo (two nodes lost)
I stopped 27019 and 27020, leaving only 27018.

- Status showed 27018 as `SECONDARY` and the other two as not reachable. **There was no primary.**
- A write was refused: `MongoServerError[NotWritablePrimary]: not primary`.
- A read with `secondaryPreferred` still worked and returned 8,000.
- After I restarted the two nodes, a primary was elected again.

Evidence: `p5-cap-no-primary.png`, `p5-cap-write-refused.png`, `p5-cap-read-ok.png`, `p5-cap-recovered.png`.

## 3. CAP: what NaijaMart chooses

The CAP idea says that when the network splits or nodes are lost, a system must choose between **consistency** (everyone sees the same, latest data) and **availability** (every request gets an answer).

MongoDB's replica set chose **consistency over availability for writes**. With no majority, the surviving node would not accept a write, because two isolated nodes could otherwise accept different changes and the data would disagree when they reconnect. Reads stayed available but could be slightly out of date (the secondary may lag behind the primary).

Which data needs which choice:

| Data | Where | Choice | Reason |
|---|---|---|---|
| Orders, payments, wallet, stock | PostgreSQL | Consistency first | Selling the same last item twice, or losing a payment, costs real money. A short "try again" is better. |
| Product catalogue and reviews | MongoDB | Availability for reads is fine | A product page that is a few seconds old does no harm. Prices are re-read from PostgreSQL at checkout (Portfolio 4). |
| Carts | Redis | Speed and availability | A lost cart is annoying, not harmful. |

## 4. Sharding design (discussion only, not built)

A replica set copies *all* data to every node, so it does not help when the data or traffic is too big for one machine. Sharding splits a collection across several replica sets (shards). A **shard key** decides which shard holds each document. A good key spreads data evenly and lets common queries go to one shard only.

I did not build a sharded cluster. This section is my design.

### 4.1 `products`
Common queries (Portfolio 4): filter by `parent_category` and `attributes.ram_gb` and sort by `price_ngn`, and look up one product by `product_id`.

| Option | Good | Bad |
|---|---|---|
| `{ product_id: "hashed" }` | Perfectly even spread | Category searches must ask every shard |
| `{ parent_category: 1 }` | Category searches hit one shard | Very few categories, so shards would be uneven, and a big category like Phones becomes one hot spot |
| `{ parent_category: 1, product_id: 1 }` | Category searches go to one shard, and `product_id` gives enough variety to split a big category | Popular categories can still be busier |

**My choice: `{ parent_category: 1, product_id: 1 }`**, because the category browse query is the most common one and this key lets it be targeted while still splitting large categories.

### 4.2 `reviews`
The main query is "newest reviews for one product". **Shard key `{ product_id: 1 }`** keeps all reviews of a product on one shard, so that query touches one shard. The risk is one extremely popular product becoming a hot spot. A compound key `{ product_id: 1, created_at: 1 }` would let MongoDB split even that product's reviews.

### 4.3 Regional hubs
NaijaMart wants fast pages in Lagos, Abuja and Port Harcourt. MongoDB's zone sharding can pin ranges of a shard key to shards placed in different regions. That would need a `hub` field in the documents, and my data does not have one, so I treat it as a future step. Customer-specific data (such as orders) is in PostgreSQL in my design, so regional placement there would be a separate decision.

### 4.4 Cost of sharding
Sharding adds servers (config servers and routers), makes queries that don't include the shard key slower, and a shard key is hard to change later. For my 8,000 products, one replica set is enough. Sharding would only be worth it once the data or traffic outgrows one machine.

## 5. PostgreSQL and the cloud (discussion only)

- **PostgreSQL** can have one or more read-only standby servers that continuously copy the primary (streaming replication). Reports and product listings could read from a standby, while orders and payments always go to the primary. The same consistency-versus-availability trade-off applies: if the standby is a few seconds behind, it can show old stock numbers, so stock checks at checkout must use the primary.
- **Cloud:** I did not use a cloud service in this portfolio. A managed service such as MongoDB Atlas or a managed PostgreSQL service would run the replica nodes in separate data centres, handle failover and backups, and cost money each month. The trade-off is less control and a recurring cost against not having to run the servers myself.

## 6. Limits I should be honest about
- All three nodes ran on one PC, so I tested the software's behaviour only, not real network failures or distance between nodes.
- I did not build sharding, PostgreSQL replication or a cloud cluster. Sections 4 and 5 are design reasoning.
- Access control was off on my local nodes (MongoDB warned about this at startup). A real deployment must turn it on.
- I did not measure replication delay.
