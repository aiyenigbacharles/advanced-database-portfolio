
# NaijaMart: Advanced Database Portfolio

**MIT 8103 Advanced Database Systems, continuous assessment 2026/2027.** Student: Charles Aiyenigba (ID 301911426).

NaijaMart is a simulated Nigerian online marketplace. Money and orders live in **PostgreSQL**, the product catalogue and reviews in **MongoDB**, and shopping carts in **Redis**. Each portfolio has its own folder with a README that explains what it shows and how to run it.

| # | Portfolio                      | Folder                                                                          | Start with                            |
| - | ------------------------------ | ------------------------------------------------------------------------------- | ------------------------------------- |
| 1 | Database design and modelling  | [`portfolio-1-database-design`](portfolio-1-database-design)                   | `README.md`, then `case-study.md` |
| 2 | Query optimisation             | [`portfolio-2-query-optimisation`](portfolio-2-query-optimisation)             | `performance-analysis.md`           |
| 3 | Transactions and concurrency   | [`portfolio-3-transactions-concurrency`](portfolio-3-transactions-concurrency) | `README.md`                         |
| 4 | NoSQL and advanced data models | [`portfolio-4-nosql`](portfolio-4-nosql)                                       | `design.md`, then `README.md`     |
| 5 | Distributed and cloud          | [`portfolio-5-distributed-cloud`](portfolio-5-distributed-cloud)               | `README.md`, then `design.md`     |

Other files: [`AI-USE.md`](AI-USE.md) is the AI-use declaration for the whole repository.

## Tools used

PostgreSQL 18, MongoDB 9.0.4 with mongosh 2.13.0, Redis (Memurai Developer) on Windows. The relational test data is generated with a fixed seed, so every run gives the same data.
