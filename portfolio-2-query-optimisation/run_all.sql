-- ===========================================================================
-- run_all.sql: regenerates ALL the Portfolio 2 evidence in one go.
--   cd portfolio-2-query-optimisation
--   psql -U postgres -d ecommerce -f run_all.sql
-- Takes about a minute. It needs the seed data (seed_reference.sql,
-- seed_transactions.sql, seed_transactions_b.sql) to be loaded first.
-- The plans are written to plans/ and the comparison table is printed at the end.
-- ===========================================================================
\set ON_ERROR_STOP on
\pset pager off

\echo '=== 0. back to the "before" state (no extra indexes, no view)'
DROP MATERIALIZED VIEW IF EXISTS mv_monthly_commission;
\i drop_indexes.sql
VACUUM ANALYZE;

\echo '=== 1. BEFORE: baseline plans and what writing costs'
\set phase before
\i capture_plans.sql
\o plans/costs/without_indexes.txt
\i index_costs.sql
\o

\echo '=== 2. create the indexes'
\i indexes.sql
VACUUM ANALYZE;

\echo '=== 3. AFTER: plans with the indexes, and what they cost'
\set phase after
\i capture_plans.sql
\o plans/costs/with_indexes.txt
\i index_costs.sql
\o

\echo '=== 4. before/after comparison'
\i compare.sql

\echo '=== 5. query rewrites'
\i rewrites.sql

\echo '=== 6. join algorithms'
\i join_algorithms.sql

\echo '=== 7. materialised view'
\i materialised_view.sql
\echo '=== done: see the plans/ folder'
