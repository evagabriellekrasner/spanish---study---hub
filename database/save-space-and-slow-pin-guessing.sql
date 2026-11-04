-- Two changes. Run once in the Supabase SQL Editor. Safe to run again.
--
-- 1. Saves space: during an assignment the site saves practice time every minute. Instead of a new row
--    each minute, those minutes are now added to the same row for that practice session. Teachers see
--    the same totals; the database just fills about 4 times slower.
--
-- 2. Slows down PIN guessing: after 5 wrong PINs for a username, the next try has to wait 1 minute,
--    and each wrong try after that waits another minute. A right PIN resets it, and so does
--    15 minutes with no wrong tries. Students who forget their PIN still ask the teacher to reset it.
--    The wrong-try counts are kept in "sequences" because those still count when the login fails
--    (a normal table write would be undone along with the failed login).
--
-- Everything runs in one transaction: if any step fails, nothing changes and logins keep working.

begin;

-- 1. One row per practice session
create or replace function student_log(n text, p text, k text, sn text, sc int, tt int, sec int, aid int) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare r int; s int; rid int;
begin
  r := _sid(n, p);
  if k not in ('practice', 'assignment', 'timed', 'submit') then raise exception 'bad kind'; end if;
  if aid is not null and not exists (select 1 from assignments where id = aid) then aid := null; end if;
  s := least(greatest(coalesce(sec, 0), 0), 3600);
  -- A minute of assignment time (no score): add it to this session's row if there is one from the last 2 hours.
  if k = 'assignment' and sc is null and tt is null and aid is not null then
    select id into rid from results
      where student_id = r and kind = 'assignment' and assignment_id = aid and score is null and total is null
        and set_name = left(coalesce(sn, ''), 120) and created_at > now() - interval '2 hours' and seconds < 4 * 3600
      order by created_at desc limit 1;
    if rid is not null then
      update results set seconds = seconds + s where id = rid;
      return;
    end if;
  end if;
  insert into results (student_id, kind, set_name, score, total, seconds, assignment_id)
  values (r, k, left(coalesce(sn, ''), 120), sc, tt, s, aid);
end $$;
grant execute on function student_log(text, text, text, text, int, int, int, int) to anon;

-- 2. Wrong-try counters: 1,024 small counters, picked by username.
do $$ begin
  for i in 0..1023 loop
    execute format('create sequence if not exists _lt%s minvalue 0 start 0', i);
    execute format('revoke all on sequence _lt%s from public, anon, authenticated', i);
  end loop;
end $$;

-- Keep the existing login check under a new name (only the first time this runs).
do $$ begin
  if not exists (select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace
                 where s.nspname = 'public' and p.proname = '_sid_core') then
    alter function _sid(text, text) rename to _sid_core;
  end if;
end $$;
revoke all on function _sid_core(text, text) from public, anon, authenticated;

-- The new login check: same answer as before, plus the wait after 5 wrong tries.
create or replace function _sid(n text, p text) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare
  q text := '_lt' || (hashtext(lower(trim(coalesce(n, '')))) & 1023);
  v bigint; f bigint; t bigint; r int;
  nw bigint := extract(epoch from clock_timestamp())::bigint;
begin
  execute format('select last_value from %I', q) into v;
  f := v / 10000000000; t := v % 10000000000;
  if nw - t > 900 then f := 0; end if;
  if f >= 5 and nw - t < 60 then raise exception 'too many tries'; end if;
  begin
    r := _sid_core(n, p);
  exception when others then
    perform setval(q, (f + 1) * 10000000000 + nw);
    raise;
  end;
  if v > 0 then perform setval(q, 0); end if;
  return r;
end $$;
revoke all on function _sid(text, text) from public, anon, authenticated;

commit;

-- Check: this should show 1024 counters and both login functions.
select (select count(*) from pg_class where relkind = 'S' and relname ~ '^_lt[0-9]+$') as counters,
       (select string_agg(proname, ', ') from pg_proc where proname in ('_sid', '_sid_core')) as login_checks;
