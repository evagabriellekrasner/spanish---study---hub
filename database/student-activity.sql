-- Lets the teacher dashboard show each student's full activity history.
-- Run once in the Supabase SQL Editor (safe to run again).
create or replace function teacher_activity(pw text, sid int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c int[];
begin
  c := _tctx(pw);
  if not exists (select 1 from class_members cm join classes k on k.id = cm.class_id
                 where k.owner_id = c[2] and cm.student_id = sid) then
    raise exception 'not your student';
  end if;
  return coalesce((select jsonb_agg(to_jsonb(y) order by y.created_at desc) from (
    select r.kind, r.set_name, r.score, r.total, r.seconds, r.created_at, a.title
    from results r left join assignments a on a.id = r.assignment_id
    where r.student_id = sid order by r.created_at desc limit 300) y), '[]'::jsonb);
end $$;
grant execute on function teacher_activity(text, int) to anon;
