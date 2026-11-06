# Portfolio 5: Distributed and cloud database design

**Case study:** NaijaMart. **Tested:** a 3-node MongoDB replica set on my own PC. **Design only:** sharding, PostgreSQL replication, cloud hosting. The reasoning is in [`design.md`](design.md).

## What is in this folder

| File | What it is |
|---|---|
| `design.md` | Replica set results, CAP trade-offs, sharding design, cloud discussion, limits |
| `commands.md` | The exact commands I ran |
| `screenshots/` | Evidence from my runs |

## How I set it up

Three `mongod` processes on ports 27018, 27019 and 27020, each in its own tab and data folder, all with `--replSet naijamartRS`. Full commands are in `commands.md`. I initiated the set once with `rs.initiate`, then loaded the Portfolio 4 data (`seed_mongo.js`) through the replica set connection.

## What I tested

| # | Test | Result | Screenshot |
|---|---|---|---|
| 1 | Set is healthy | One primary, two secondaries, all `health=1` | `p5-replica-set-status.png` |
| 2 | Data is on a secondary | 8,000 products, 67,544 reviews | `p5-secondary-has-data.png` |
| 3 | Write on primary reaches secondary | Appears on the secondary | `p5-write-replicates.png` |
| 4 | Write sent to a secondary | Refused | `p5-secondary-refuses-write.png` |
| 5 | Stop the primary (27018) | 27019 elected primary automatically | `p5-failover-before.png`, `p5-failover-after.png` |
| 6 | Write with one node down | Succeeded | `p5-write-during-outage.png` |
| 7 | Restart the stopped node | Rejoined as secondary and caught up | `p5-node-rejoined.png`, `p5-node-caught-up.png` |
| 8 | Stop two nodes (no majority) | No primary | `p5-cap-no-primary.png` |
| 9 | Write with no primary | `NotWritablePrimary` | `p5-cap-write-refused.png` |
| 10 | Read with no primary | Still worked (8,000) | `p5-cap-read-ok.png` |
| 11 | Restart both nodes | Primary elected again | `p5-cap-recovered.png` |

## Main finding

With one node down, the set elected a new primary and kept accepting writes. With two nodes down, it refused writes and kept serving reads. That is a choice of consistency over write availability, and it is the right one for NaijaMart's money data (see `design.md`, section 3).

## Limits
All nodes ran on one PC, so this tests behaviour, not real network failure. Sharding, PostgreSQL replication and cloud hosting are discussed in `design.md` but not built. The demo field I wrote during the failover test was removed afterwards.
