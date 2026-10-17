# AI Use Declaration

**Course:** MIT 8103 Advanced Database Systems, First Semester Continuous Assessment 2026/2027
**Student:** Charles Aiyenigba
**Student ID:** 301911426
**Date:** [TBA]

This declaration follows section 11 of the assessment brief: the AI tool used, what it was used for, and how the output was reviewed, corrected, tested or verified by me.

---

## 1. AI tool used

**Claude** (Anthropic), used through the claude.ai chat interface. Model in the sessions that produced these files: Claude Sonnet 5.5.

## 2. What the AI tool was used for

| File | Portfolio | What the AI generated |
|---|---|---|
| `schema.sql` | 1 | The SQL for all 11 tables: keys, constraints, composite foreign keys and comments |
| `constraint_tests.sql` | 1 | The test script: good fixture data and 44 failing statements, one per rule |
| `er-diagram.dbml` | 1 | The diagram source for dbdiagram.io |
| `case-study.md` | 1 | The written description of the NaijaMart case study |

The AI also discussed design choices with me in conversation, for example where stock lives, how the wallet ledger works, and how split orders become deliveries.

## 3. What I did myself

*Edit this section so it is true for you. The assessment expects it, and it is what you will be asked about if you are selected for verification.*

- [ ] I chose the case study (NaijaMart) and decided the scope: which tables stay relational and which move to NoSQL.
- [ ] I made these design decisions: [list the ones you decided, for example "each product has one seller", "wallet as a ledger plus cached balance", "reviews go to MongoDB"].
- [ ] I created the GitHub repository and made the commits myself.
- [ ] I exported the ER diagram from dbdiagram.io myself.

## 4. How I reviewed, corrected, tested and verified the output

*Fill in only what you actually did. Do not tick anything you have not done.*

- [ ] I read `schema.sql` line by line and can explain every constraint, including the composite foreign keys.
- [ ] I ran `schema.sql` twice on my own PostgreSQL installation (version: [add]) and both runs finished with `COMMIT`. Screenshot: [file name].
- [ ] I ran `\dt` and confirmed all 11 tables exist. Screenshot: [file name].
- [ ] I ran `constraint_tests.sql`. Result: [passed / failed / total]. Screenshot: [file name].
- [ ] Problems I found and how I fixed them: [describe, or write "none"].
- [ ] Changes I made to the AI's output: [describe, or write "none"].

**Note on testing:** the AI could not run the final 11 table schema or the 44 tests in the session where it wrote them, because that session had no PostgreSQL. The first run of these files on a real database was done by me, on my own machine.

## 5. Responsibility

I am responsible for the accuracy, originality and understanding of everything in this portfolio, and I can explain every file listed above.
