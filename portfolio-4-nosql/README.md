# Portfolio 4: NoSQL and Advanced Data Models

**Case study:** NairaFlow Digital Bank<br>
**Database:** MongoDB Atlas (free tier, AWS eu-west-3, three-node replica set), managed with MongoDB Compass

## Summary

NairaFlow's PostgreSQL data was exported as documents and imported into MongoDB: customer
profiles with accounts and KYC embedded, and transaction events with ledger lines embedded.
Schema validation, unique and multikey indexes, an aggregation pipeline cross-checked against
PostgreSQL (**exact match**), and a `$graphLookup` traversal that **detected a planted
money-mule ring** demonstrate where the document model fits a bank and where it does not.

Full write-up: **[nosql-design.md](nosql-design.md)**

## Contents

| File | Purpose |
| --- | --- |
| [export-views.sql](export-views.sql) | PostgreSQL views that output MongoDB Extended JSON documents |
| [data/customers.json](data/customers.json) | Exported customer documents (sample; the events file is excluded via `.gitignore`) |
| [mongo/01-collections.js](mongo/01-collections.js) | Collections with `$jsonSchema` validation |
| [mongo/02-validation-test.js](mongo/02-validation-test.js) | Invalid insert, rejected by validation |
| [mongo/03-indexes.js](mongo/03-indexes.js) | Unique, multikey and compound indexes |
| [mongo/04-queries.js](mongo/04-queries.js) | D1–D5: one-read profile, statement + explain, aggregation, graph traversal, flexible schema |
| [nosql-design.md](nosql-design.md) | Model decisions, results, suitability and risks |
| [screenshots/](screenshots/) | Evidence for every step |

## Key results

| Test | Result |
| --- | --- |
| Import | 1,001 customers and 51,658 transaction events, all passing validation |
| Types | Money as Decimal128, dates as BSON Date |
| Validation | Invalid BVN and negative balance rejected |
| Profile lookup | 1 key and 1 document examined (EXPRESS_IXSCAN on a unique multikey index) |
| Statement query | 8 documents examined with the index vs 51,658 without (29 ms vs 351 ms) |
| Aggregation | Six daily totals identical to PostgreSQL |
| Graph traversal | Ring 2001 → 2002 → 2003 → 2001 detected |

## How to reproduce

1. With Portfolios 1–3 complete in PostgreSQL, run `export-views.sql`.
2. Export both files with the `\copy` commands in the Appendix of `nosql-design.md`.
3. In mongosh, run `mongo/01-collections.js`, import the two JSON files with Compass, then run `mongo/03-indexes.js`.
4. Run each block in `mongo/04-queries.js` one at a time.