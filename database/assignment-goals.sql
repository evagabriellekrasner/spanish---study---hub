-- Assignment activities and goals. Run once in the Supabase SQL Editor (safe to run again).
alter table assignments add column if not exists mode text;
alter table assignments add column if not exists goal text not null default 'minutes';
alter table assignments add column if not exists target int;

create or replace function _adone(a assignments, sid int) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'done_seconds', coalesce(sum(r.seconds), 0),
    'rounds', count(*) filter (where r.total > 0),
    'best', coalesce(max(round(100.0 * r.score / r.total)) filter (where r.total > 0), 0),
    'done', case a.goal
      when 'finish' then count(*) filter (where r.total > 0) >= 1
      when 'score' then coalesce(max(round(100.0 * r.score / r.total)) filter (where r.total > 0), 0) >= coalesce(a.target, 0)
      else coalesce(sum(r.seconds), 0) >= a.minutes * 60 end)
  from results r where r.assignment_id = a.id and r.student_id = sid
$$;
revoke all on function _adone(assignments, int) from public, anon, authenticated;

create or replace function teacher_assign3(pw text, t text, sn text, m int, d date, cid int, md text, gl text, tg int) returns int
language plpgsql security definer set search_path = public as $$
declare r int;
begin
  perform _teach(pw);
  if gl not in ('minutes', 'finish', 'score') then raise exception 'bad goal'; end if;
  if gl = 'minutes' and (m < 1 or m > 240) then raise exception 'bad minutes'; end if;
  if gl = 'score' and (tg < 1 or tg > 100) then raise exception 'bad score'; end if;
  if cid is not null and not exists (select 1 from classes where id = cid) then raise exception 'bad class'; end if;
  insert into assignments (title, set_name, minutes, due, class_id, mode, goal, target)
  values (left(t, 120), left(sn, 120), case when gl = 'minutes' then m else 0 end, d, cid, nullif(left(md, 20), ''), gl, case when gl = 'score' then tg end)
  returning id into r;
  return r;
end $$;

create or replace function student_get(n text, p text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r int; o jsonb;
begin
  r := _sid(n, p);
  select jsonb_build_object(
    'name', (select name from students where id = r),
    'role', (select role from students where id = r),
    'weak', (select weak from students where id = r),
    'classes', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by lower(c.name))
        from classes c join class_members cm on cm.class_id = c.id where cm.student_id = r), '[]'::jsonb),
    'results', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc)
        from (select kind, set_name, score, total, seconds, assignment_id, created_at
              from results where student_id = r order by created_at desc limit 60) x), '[]'::jsonb),
    'assignments', coalesce((select jsonb_agg(jsonb_build_object(
        'id', a.id, 'title', a.title, 'set_name', a.set_name, 'minutes', a.minutes, 'due', a.due,
        'class', (select name from classes where id = a.class_id),
        'mode', a.mode, 'goal', a.goal, 'target', a.target) || _adone(a, r)
        order by a.created_at desc) from assignments a
        where a.active and (a.class_id is null or exists (select 1 from class_members cm where cm.class_id = a.class_id and cm.student_id = r))), '[]'::jsonb)
  ) into o;
  return o;
end $$;

create or replace function teacher_report(pw text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o jsonb;
begin
  perform _teach(pw);
  select jsonb_build_object(
    'classes', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.name, 'code', c.code,
        'members', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by lower(s.name))
            from class_members cm join students s on s.id = cm.student_id where cm.class_id = c.id), '[]'::jsonb))
        order by lower(c.name)) from classes c), '[]'::jsonb),
    'students', coalesce((select jsonb_agg(jsonb_build_object(
        'id', s.id, 'name', s.name, 'last_seen', s.last_seen, 'role', s.role,
        'weak', (select count(*) from jsonb_object_keys(s.weak)),
        'rounds', (select count(*) from results r where r.student_id = s.id),
        'seconds', coalesce((select sum(seconds) from results r where r.student_id = s.id), 0))
        order by lower(s.name)) from students s), '[]'::jsonb),
    'assignments', coalesce((select jsonb_agg(jsonb_build_object(
        'id', a.id, 'title', a.title, 'set_name', a.set_name, 'minutes', a.minutes, 'due', a.due, 'active', a.active,
        'class_id', a.class_id, 'class', (select name from classes where id = a.class_id),
        'mode', a.mode, 'goal', a.goal, 'target', a.target,
        'progress', coalesce((select jsonb_agg(jsonb_build_object('student', s.name, 'seconds', x.sec, 'right', x.sc, 'total', x.tt) || _adone(a, s.id))
            from (select student_id, sum(seconds) sec, sum(coalesce(score, 0)) sc, sum(coalesce(total, 0)) tt
                  from results where assignment_id = a.id group by student_id) x
            join students s on s.id = x.student_id), '[]'::jsonb))
        order by a.created_at desc) from assignments a), '[]'::jsonb),
    'recent', coalesce((select jsonb_agg(to_jsonb(y) order by y.created_at desc)
        from (select s.name, r.kind, r.set_name, r.score, r.total, r.seconds, r.created_at
              from results r join students s on s.id = r.student_id order by r.created_at desc limit 40) y), '[]'::jsonb)
  ) into o;
  return o;
end $$;

grant execute on function teacher_assign3(text, text, text, int, date, int, text, text, int) to anon;
grant execute on function student_get(text, text) to anon;
grant execute on function teacher_report(text) to anon;
