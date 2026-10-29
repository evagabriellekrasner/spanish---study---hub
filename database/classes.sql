-- Classes: run once in the Supabase SQL Editor (safe to run again).
create table if not exists classes (
  id serial primary key,
  name text not null,
  code text not null unique,
  created_at timestamptz default now()
);
create table if not exists class_members (
  class_id int not null references classes(id) on delete cascade,
  student_id int not null references students(id) on delete cascade,
  primary key (class_id, student_id)
);
alter table assignments add column if not exists class_id int references classes(id) on delete cascade;
alter table classes enable row level security;
alter table class_members enable row level security;

create or replace function teacher_class(pw text, act text, nm text, cid int, sid int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c text; r int; i int;
begin
  perform _teach(pw);
  if act = 'create' then
    nm := trim(nm);
    if length(nm) < 1 or length(nm) > 60 then raise exception 'bad name'; end if;
    loop
      c := '';
      for i in 1..6 loop c := c || substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random() * 31)::int, 1); end loop;
      exit when not exists (select 1 from classes where code = c);
    end loop;
    insert into classes (name, code) values (nm, c) returning id into r;
    return jsonb_build_object('id', r, 'code', c);
  elsif act = 'delete' then
    delete from classes where id = cid;
  elsif act = 'remove' then
    delete from class_members where class_id = cid and student_id = sid;
  end if;
  return null;
end $$;

create or replace function student_join(n text, p text, code text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r int; c classes;
begin
  r := _sid(n, p);
  select * into c from classes where classes.code = upper(trim(student_join.code));
  if c.id is null then raise exception 'bad code'; end if;
  insert into class_members (class_id, student_id) values (c.id, r) on conflict do nothing;
  return jsonb_build_object('id', c.id, 'name', c.name);
end $$;

create or replace function teacher_assign2(pw text, t text, sn text, m int, d date, cid int) returns int
language plpgsql security definer set search_path = public as $$
declare r int;
begin
  perform _teach(pw);
  if m < 1 or m > 240 then raise exception 'bad minutes'; end if;
  if cid is not null and not exists (select 1 from classes where id = cid) then raise exception 'bad class'; end if;
  insert into assignments (title, set_name, minutes, due, class_id) values (left(t, 120), left(sn, 120), m, d, cid) returning id into r;
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
        'done_seconds', coalesce((select sum(seconds) from results where student_id = r and assignment_id = a.id), 0))
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
        'progress', coalesce((select jsonb_agg(jsonb_build_object('student', s.name, 'seconds', x.sec, 'right', x.sc, 'total', x.tt))
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

grant execute on function teacher_class(text, text, text, int, int) to anon;
grant execute on function student_join(text, text, text) to anon;
grant execute on function teacher_assign2(text, text, text, int, date, int) to anon;
grant execute on function student_get(text, text) to anon;
grant execute on function teacher_report(text) to anon;
