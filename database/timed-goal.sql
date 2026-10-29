-- Adds the timed goal ("answer 50 words in 8 minutes with at least 80%").
-- Run once in the Supabase SQL Editor (safe to run again).

alter table assignments add column if not exists words int;

create or replace function _adone(a assignments, sid int) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'words', a.words,
    'done_seconds', coalesce(sum(r.seconds), 0),
    'rounds', count(*) filter (where r.total > 0),
    'best', coalesce(max(round(100.0 * r.score / r.total)) filter (where r.total > 0), 0),
    'right', coalesce(sum(r.score) filter (where r.total > 0), 0),
    'answered', coalesce(sum(r.total) filter (where r.total > 0), 0),
    'tries', count(*) filter (where r.kind = 'timed'),
    'tbest', (select jsonb_build_object('n', x.total, 'r', x.score) from results x
              where x.assignment_id = a.id and x.student_id = sid and x.kind = 'timed' and x.total > 0
              order by (100 * x.score >= coalesce(a.target, 0) * x.total) desc, x.total desc, x.score desc limit 1),
    'done', case a.goal
      when 'finish' then count(*) filter (where r.total > 0) >= 1
      when 'score' then coalesce(max(round(100.0 * r.score / r.total)) filter (where r.total > 0), 0) >= coalesce(a.target, 0)
      when 'terms' then coalesce(sum(r.score) filter (where r.total > 0), 0) >= a.minutes
        and coalesce(sum(r.total) filter (where r.total > 0), 0) > 0
        and 100.0 * sum(r.score) filter (where r.total > 0) / sum(r.total) filter (where r.total > 0) >= coalesce(a.target, 0)
      when 'timed' then count(*) filter (where r.kind = 'timed' and r.total >= coalesce(a.words, 1)
        and 100 * r.score >= coalesce(a.target, 0) * r.total) > 0
      else coalesce(sum(r.seconds), 0) >= a.minutes * 60 end)
  from results r where r.assignment_id = a.id and r.student_id = sid
$$;
revoke all on function _adone(assignments, int) from public, anon, authenticated;

create or replace function teacher_assign4(pw text, t text, sn text, m int, d date, cid int, md text, gl text, tg int, w int) returns int
language plpgsql security definer set search_path = public as $$
declare c int[]; r int;
begin
  c := _tctx(pw);
  if gl not in ('minutes', 'terms', 'timed') then raise exception 'bad goal'; end if;
  if gl = 'minutes' and (m < 1 or m > 240) then raise exception 'bad minutes'; end if;
  if gl = 'terms' and (m < 1 or m > 1000 or tg < 1 or tg > 100) then raise exception 'bad terms'; end if;
  if gl = 'timed' and (m < 1 or m > 60 or w < 1 or w > 1000 or tg < 1 or tg > 100) then raise exception 'bad timed'; end if;
  if cid is not null and not exists (select 1 from classes where id = cid and owner_id = c[2]) then raise exception 'bad class'; end if;
  insert into assignments (title, set_name, minutes, due, class_id, mode, goal, target, words, owner_id)
  values (left(t, 120), left(sn, 120), m, d, cid, nullif(left(md, 20), ''), gl,
          case when gl in ('terms', 'timed') then tg end, case when gl = 'timed' then w end, c[2])
  returning id into r;
  return r;
end $$;
grant execute on function teacher_assign4(text, text, text, int, date, int, text, text, int, int) to anon;

create or replace function teacher_report(pw text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c int[]; o jsonb;
begin
  c := _tctx(pw);
  select jsonb_build_object(
    'lib', jsonb_build_object('id', c[2], 'name', (select name from students where id = c[2]), 'mine', c[1] = c[2],
        'members', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by lower(s.name))
            from lib_members m join students s on s.id = m.teacher_id where m.owner_id = c[2]), '[]'::jsonb)),
    'classes', coalesce((select jsonb_agg(jsonb_build_object(
        'id', k.id, 'name', k.name, 'code', k.code,
        'members', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by lower(s.name))
            from class_members cm join students s on s.id = cm.student_id where cm.class_id = k.id), '[]'::jsonb))
        order by lower(k.name)) from classes k where k.owner_id = c[2]), '[]'::jsonb),
    'students', coalesce((select jsonb_agg(jsonb_build_object(
        'id', s.id, 'name', s.name, 'last_seen', s.last_seen, 'role', s.role,
        'weak', (select count(*) from jsonb_object_keys(s.weak)), 'weakd', s.weak,
        'rounds', (select count(*) from results r where r.student_id = s.id),
        'seconds', coalesce((select sum(seconds) from results r where r.student_id = s.id), 0))
        order by lower(s.name)) from students s
        where s.id in (select cm.student_id from class_members cm join classes k on k.id = cm.class_id where k.owner_id = c[2])), '[]'::jsonb),
    'assignments', coalesce((select jsonb_agg(jsonb_build_object(
        'id', a.id, 'title', a.title, 'set_name', a.set_name, 'minutes', a.minutes, 'due', a.due, 'active', a.active,
        'class_id', a.class_id, 'class', (select name from classes where id = a.class_id),
        'mode', a.mode, 'goal', a.goal, 'target', a.target, 'words', a.words,
        'progress', coalesce((select jsonb_agg(jsonb_build_object('student', s.name, 'seconds', x.sec, 'right', x.sc, 'total', x.tt) || _adone(a, s.id))
            from (select student_id, sum(seconds) sec, sum(coalesce(score, 0)) sc, sum(coalesce(total, 0)) tt
                  from results where assignment_id = a.id group by student_id) x
            join students s on s.id = x.student_id), '[]'::jsonb))
        order by a.created_at desc) from assignments a where a.owner_id = c[2]), '[]'::jsonb),
    'recent', coalesce((select jsonb_agg(to_jsonb(y) order by y.created_at desc)
        from (select s.name, r.kind, r.set_name, r.score, r.total, r.seconds, r.created_at
              from results r join students s on s.id = r.student_id
              where s.id in (select cm.student_id from class_members cm join classes k on k.id = cm.class_id where k.owner_id = c[2])
              order by r.created_at desc limit 40) y), '[]'::jsonb)
  ) into o;
  return o;
end $$;

grant execute on function teacher_report(text) to anon;
