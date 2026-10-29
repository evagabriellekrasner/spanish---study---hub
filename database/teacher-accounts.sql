-- Teacher accounts: run once in the Supabase SQL Editor.
alter table students add column if not exists role text not null default 'student';

create or replace function teacher_signup(n text, p text, pw text) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare r int;
begin
  perform _teach(pw);
  n := trim(n);
  if length(n) < 1 or length(n) > 30 then raise exception 'bad name'; end if;
  if p !~ '^[0-9]{4}$' then raise exception 'bad pin'; end if;
  if exists (select 1 from students where lower(name) = lower(n)) then raise exception 'name taken'; end if;
  insert into students (name, pin_hash, role) values (n, crypt(p, gen_salt('bf')), 'teacher') returning id into r;
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
    'results', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc)
        from (select kind, set_name, score, total, seconds, assignment_id, created_at
              from results where student_id = r order by created_at desc limit 60) x), '[]'::jsonb),
    'assignments', coalesce((select jsonb_agg(jsonb_build_object(
        'id', a.id, 'title', a.title, 'set_name', a.set_name, 'minutes', a.minutes, 'due', a.due,
        'done_seconds', coalesce((select sum(seconds) from results where student_id = r and assignment_id = a.id), 0))
        order by a.created_at desc) from assignments a where a.active), '[]'::jsonb)
  ) into o;
  return o;
end $$;

grant execute on function teacher_signup(text, text, text) to anon;
grant execute on function student_get(text, text) to anon;
