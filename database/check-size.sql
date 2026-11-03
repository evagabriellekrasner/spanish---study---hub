-- Shows how full the database is. It only reads, so it's safe to run any time, as often as you like.
-- Paste into the Supabase SQL Editor and click Run. The free plan holds 500 MB.

-- 1. Total space used
select pg_size_pretty(pg_database_size(current_database())) as used,
       '500 MB' as free_plan_limit,
       round(100.0 * pg_database_size(current_database()) / (500 * 1024 * 1024), 1) || '%' as percent_full;

-- 2. The biggest tables and how many rows each has
select relname as table_name,
       pg_size_pretty(pg_total_relation_size(relid)) as size,
       n_live_tup as rows
from pg_stat_user_tables
order by pg_total_relation_size(relid) desc
limit 10;
