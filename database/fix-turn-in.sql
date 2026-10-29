-- Fixes Turn in and timed tries: lets the site save those two kinds of results.
-- Run once in the Supabase SQL Editor (safe to run again).
create or replace function student_log(n text, p text, k text, sn text, sc int, tt int, sec int, aid int) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare r int;
begin
  r := _sid(n, p);
  if k not in ('practice', 'assignment', 'timed', 'submit') then raise exception 'bad kind'; end if;
  if aid is not null and not exists (select 1 from assignments where id = aid) then aid := null; end if;
  insert into results (student_id, kind, set_name, score, total, seconds, assignment_id)
  values (r, k, left(coalesce(sn, ''), 120), sc, tt, least(greatest(coalesce(sec, 0), 0), 3600), aid);
end $$;
grant execute on function student_log(text, text, text, text, int, int, int, int) to anon;
