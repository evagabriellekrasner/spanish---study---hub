-- Adds the "Get a number of terms right, at a minimum %" assignment goal.
-- The number of terms is stored in the minutes column and the % in target.

create or replace function _adone(a assignments, sid int) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'done_seconds', coalesce(sum(r.seconds), 0),
    'rounds', count(*) filter (where r.total > 0),
    'best', coalesce(max(round(100.0 * r.score / r.total)) filter (where r.total > 0), 0),
    'right', coalesce(sum(r.score) filter (where r.total > 0), 0),
    'answered', coalesce(sum(r.total) filter (where r.total > 0), 0),
    'done', case a.goal
      when 'finish' then count(*) filter (where r.total > 0) >= 1
      when 'score' then coalesce(max(round(100.0 * r.score / r.total)) filter (where r.total > 0), 0) >= coalesce(a.target, 0)
      when 'terms' then coalesce(sum(r.score) filter (where r.total > 0), 0) >= a.minutes
        and coalesce(sum(r.total) filter (where r.total > 0), 0) > 0
        and 100.0 * sum(r.score) filter (where r.total > 0) / sum(r.total) filter (where r.total > 0) >= coalesce(a.target, 0)
      else coalesce(sum(r.seconds), 0) >= a.minutes * 60 end)
  from results r where r.assignment_id = a.id and r.student_id = sid
$$;
revoke all on function _adone(assignments, int) from public, anon, authenticated;

create or replace function teacher_assign3(pw text, t text, sn text, m int, d date, cid int, md text, gl text, tg int) returns int
language plpgsql security definer set search_path = public as $$
declare c int[]; r int;
begin
  c := _tctx(pw);
  if gl not in ('minutes', 'finish', 'score', 'terms') then raise exception 'bad goal'; end if;
  if gl = 'minutes' and (m < 1 or m > 240) then raise exception 'bad minutes'; end if;
  if gl = 'score' and (tg < 1 or tg > 100) then raise exception 'bad score'; end if;
  if gl = 'terms' and (m < 1 or m > 1000 or tg < 1 or tg > 100) then raise exception 'bad terms'; end if;
  if cid is not null and not exists (select 1 from classes where id = cid and owner_id = c[2]) then raise exception 'bad class'; end if;
  insert into assignments (title, set_name, minutes, due, class_id, mode, goal, target, owner_id)
  values (left(t, 120), left(sn, 120), case when gl in ('minutes', 'terms') then m else 0 end, d, cid, nullif(left(md, 20), ''), gl,
          case when gl in ('score', 'terms') then tg end, c[2])
  returning id into r;
  return r;
end $$;
grant execute on function teacher_assign3(text, text, text, int, date, int, text, text, int) to anon;
