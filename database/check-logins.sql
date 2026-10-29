-- Read-only check. It changes nothing. Run it in the Supabase SQL Editor and send a screenshot of the result.
select
  (select count(*) from students) as accounts,
  (select count(*) from students where role = 'teacher') as teachers,
  (select count(*) from students where pin_hash like '$2%') as good_pins,
  (select string_agg(n.nspname, ',') from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pgcrypto') as pgcrypto_in,
  (select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ') ' || coalesce(array_to_string(p.proconfig, ' '), 'no-path'), ' | ')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in ('_sid', 'student_get', 'student_join')) as functions;
