# AI Use Declaration

**Course:** MIT 8103 Advanced Database Systems, First Semester Continuous Assessment 2026/2027
**Student:** Charles Aiyenigba
**Student ID:** 301911426
**Date:** 7th November 2026

This declaration covers all five portfolios in this repository (section 11 of the assessment brief).

## 1. Tool used

**Claude** (Anthropic), Sonnet 5.5, through the Claude app. No other AI tool was used for the database work.

## 2. What the AI tool was used for

| Portfolio             | What Claude drafted                                                                                                                                                                                              |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. Design             | `schema.sql`, `constraint_tests.sql`, `case-study.md`, `normalization.md` and the README                                                                                                                |
| 2. Query optimisation | The seed scripts, `queries.sql`, `indexes.sql`, `compare.sql`, `rewrites.sql`, `join_algorithms.sql`, `materialised_view.sql`, `index_costs.sql`, `run_all.sql` &  `performance-analysis.md` |
| 3. Transactions       | The demo scripts `00` to `06` and `99_cleanup.sql`& `demo_window.sql`                                                                                                                                    |
| 4. NoSQL              | `seed_mongo.js`, `explain_queries.js`, the index scripts, `export_*.sql`, `sync_prices.js`, `redis_cart_demo.md`& `design.md`                                                                       |
| 5. Distributed        | `design.md`, `README.md` and `commands.md`                                                                                                                                                                 |

Claude also explained some concepts to me.

## 3. What I did myself

- I chose the case study (NaijaMart) and decided the scope: which data stays in PostgreSQL, which goes to MongoDB and Redis.
- I made the design decisions.
- I installed and ran PostgreSQL, MongoDB, Redis (Memurai) and the three-node MongoDB replica set on my own PC.
- I ran the scripts and commands, took the screenshots, and made the Git commits and pushes.
- The numbers in the READMEs come from my runs. When I found output that was not from my own run, I deleted it.
- I corrected mistakes as they came up, for example commands typed in the wrong shell, missing files and out-of-date README sections.

## 4. How I reviewed and verified the output

- I ran each script and compared what happened with what the write-up claimed.
- I read the drafted files and edited what I did not understand.
- I checked that results were repeatable (seeded data, fixed dates, before and after runs).

*Signed: Charles Aiyenigba, 7 November 2026*
