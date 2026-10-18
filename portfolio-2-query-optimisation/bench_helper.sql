-- ===========================================================================
-- bench_helper.sql: shared measuring tool, loaded by the other scripts with \i
--
-- pg_temp.bench(query) runs EXPLAIN (ANALYZE, BUFFERS) on the query 3 times and
-- returns each run's time and plan. The result rows are collected in the temp
-- table "runs". The view "median_runs" keeps the MEDIAN run of each label (the
-- 2nd fastest of 3), so one slow cold-cache run does not distort the result.
--
-- Everything is temporary (it disappears when psql closes) and can be loaded
-- again in the same session.
-- ===========================================================================
DROP VIEW     IF EXISTS pg_temp.median_runs;
DROP TABLE    IF EXISTS pg_temp.runs;
DROP FUNCTION IF EXISTS pg_temp.bench(text);

CREATE FUNCTION pg_temp.bench(q text)
RETURNS TABLE (run_no integer, ms numeric, plan text)
LANGUAGE plpgsql AS $f$
DECLARE
    i    integer;
    line text;
    buf  text;
BEGIN
    FOR i IN 1..3 LOOP
        buf := '';
        FOR line IN EXECUTE 'EXPLAIN (ANALYZE, BUFFERS) ' || q LOOP
            buf := buf || line || E'\n';
        END LOOP;
        run_no := i;
        ms     := (regexp_match(buf, 'Execution Time: ([0-9.]+) ms'))[1]::numeric;
        plan   := buf;
        RETURN NEXT;
    END LOOP;
END
$f$;

CREATE TEMP TABLE runs (label text, title text, query text, run_no integer, ms numeric, plan text);

CREATE TEMP VIEW median_runs AS
SELECT r.label, r.title, r.query, r.ms AS median_ms, r.plan,
       (SELECT array_agg(x.ms ORDER BY x.run_no) FROM runs x WHERE x.label = r.label) AS all_ms
FROM (SELECT *, row_number() OVER (PARTITION BY label ORDER BY ms) AS rk FROM runs) r
WHERE r.rk = 2;
