-- Lets teachers see each student's weak spots. Run once in the Supabase SQL Editor (safe to run again).
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
        'mode', a.mode, 'goal', a.goal, 'target', a.target,
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
