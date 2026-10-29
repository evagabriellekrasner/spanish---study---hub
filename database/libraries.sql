-- Separate library per teacher. Run once in the Supabase SQL Editor (safe to run again).
-- Your current sets, classes and assignments move into the first teacher account's library.

create table if not exists libraries (
  owner_id int primary key references students(id) on delete cascade,
  data jsonb not null default '{}',
  updated_at timestamptz default now()
);
create table if not exists lib_members (
  owner_id int not null references students(id) on delete cascade,
  teacher_id int not null references students(id) on delete cascade,
  primary key (owner_id, teacher_id)
);
alter table libraries enable row level security;
alter table lib_members enable row level security;
alter table classes add column if not exists owner_id int references students(id) on delete cascade;
alter table assignments add column if not exists owner_id int references students(id) on delete cascade;

do $$
declare t int;
begin
  select id into t from students where role = 'teacher' order by id limit 1;
  if t is not null then
    update classes set owner_id = t where owner_id is null;
    update assignments set owner_id = t where owner_id is null;
    insert into libraries (owner_id, data)
      values (t, coalesce((select data from sets where id = 1), '{}'::jsonb))
      on conflict (owner_id) do nothing;
  end if;
end $$;

-- Checks a teacher login sent as {"n":name,"p":pin,"l":library}. Returns {teacher id, library id}.
create or replace function _tctx(pw text) returns int[]
language plpgsql security definer set search_path = public, extensions as $$
declare j jsonb; t int; l int;
begin
  begin j := pw::jsonb; exception when others then j := null; end;
  if j is null or jsonb_typeof(j) <> 'object' then raise exception 'wrong passcode'; end if;
  select id into t from students
    where lower(name) = lower(trim(j->>'n')) and role = 'teacher' and pin_hash = crypt(j->>'p', pin_hash);
  if t is null then raise exception 'wrong passcode'; end if;
  l := case when coalesce(j->>'l', '') ~ '^[0-9]{1,9}$' then (j->>'l')::int else t end;
  if l <> t and not exists (select 1 from lib_members where owner_id = l and teacher_id = t) then
    raise exception 'no access';
  end if;
  return array[t, l];
end $$;
revoke all on function _tctx(text) from public, anon, authenticated;

create or replace function _slib(sid int) returns int
language sql stable security definer set search_path = public as $$
  select c.owner_id from class_members cm join classes c on c.id = cm.class_id
  where cm.student_id = sid order by c.id limit 1
$$;
revoke all on function _slib(int) from public, anon, authenticated;

drop function if exists save_sets(text, jsonb);
create function save_sets(pw text, d jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare c int[];
begin
  c := _tctx(pw);
  insert into libraries (owner_id, data) values (c[2], d)
    on conflict (owner_id) do update set data = excluded.data, updated_at = now();
end $$;

create or replace function lib_get(n text, p text, l int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r int; t boolean; lib int;
begin
  r := _sid(n, p);
  t := (select role = 'teacher' from students where id = r);
  if t then
    lib := case when l is not null and (l = r or exists (select 1 from lib_members where owner_id = l and teacher_id = r)) then l else r end;
  else
    lib := _slib(r);
  end if;
  return jsonb_build_object(
    'id', lib,
    'name', (select name from students where id = lib),
    'mine', lib = r,
    'data', coalesce((select data from libraries where owner_id = lib), '{}'::jsonb),
    'libs', case when t then coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'mine', s.id = r) order by s.id <> r, lower(s.name))
        from students s where s.id = r or s.id in (select owner_id from lib_members where teacher_id = r)), '[]'::jsonb) else '[]'::jsonb end);
end $$;

create or replace function teacher_class(pw text, act text, nm text, cid int, sid int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c int[]; k text; r int; i int;
begin
  c := _tctx(pw);
  if act = 'create' then
    nm := trim(nm);
    if length(nm) < 1 or length(nm) > 60 then raise exception 'bad name'; end if;
    loop
      k := '';
      for i in 1..6 loop k := k || substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random() * 31)::int, 1); end loop;
      exit when not exists (select 1 from classes where code = k);
    end loop;
    insert into classes (name, code, owner_id) values (nm, k, c[2]) returning id into r;
    return jsonb_build_object('id', r, 'code', k);
  elsif act = 'delete' then
    delete from classes where id = cid and owner_id = c[2];
  elsif act = 'remove' then
    delete from class_members where student_id = sid
      and class_id = (select id from classes where id = cid and owner_id = c[2]);
  elsif act = 'share' then
    if c[1] <> c[2] then raise exception 'not owner'; end if;
    select id into r from students where lower(name) = lower(trim(nm)) and role = 'teacher';
    if r is null then raise exception 'no teacher'; end if;
    if r = c[1] then raise exception 'is you'; end if;
    insert into lib_members (owner_id, teacher_id) values (c[1], r) on conflict do nothing;
  elsif act = 'unshare' then
    if c[1] <> c[2] then raise exception 'not owner'; end if;
    delete from lib_members where owner_id = c[1] and teacher_id = sid;
  elsif act = 'leave' then
    delete from lib_members where owner_id = c[2] and teacher_id = c[1];
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
  delete from class_members where student_id = r and class_id <> c.id;
  insert into class_members (class_id, student_id) values (c.id, r) on conflict do nothing;
  return jsonb_build_object('id', c.id, 'name', c.name);
end $$;

create or replace function teacher_assign3(pw text, t text, sn text, m int, d date, cid int, md text, gl text, tg int) returns int
language plpgsql security definer set search_path = public as $$
declare c int[]; r int;
begin
  c := _tctx(pw);
  if gl not in ('minutes', 'finish', 'score') then raise exception 'bad goal'; end if;
  if gl = 'minutes' and (m < 1 or m > 240) then raise exception 'bad minutes'; end if;
  if gl = 'score' and (tg < 1 or tg > 100) then raise exception 'bad score'; end if;
  if cid is not null and not exists (select 1 from classes where id = cid and owner_id = c[2]) then raise exception 'bad class'; end if;
  insert into assignments (title, set_name, minutes, due, class_id, mode, goal, target, owner_id)
  values (left(t, 120), left(sn, 120), case when gl = 'minutes' then m else 0 end, d, cid, nullif(left(md, 20), ''), gl, case when gl = 'score' then tg end, c[2])
  returning id into r;
  return r;
end $$;

create or replace function teacher_end(pw text, aid int) returns void
language plpgsql security definer set search_path = public as $$
declare c int[];
begin
  c := _tctx(pw);
  update assignments set active = false where id = aid and owner_id = c[2];
end $$;

create or replace function teacher_student(pw text, sid int, act text, newpin text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare c int[];
begin
  c := _tctx(pw);
  if not exists (select 1 from class_members cm join classes k on k.id = cm.class_id join students s on s.id = cm.student_id
                 where cm.student_id = sid and k.owner_id = c[2] and s.role <> 'teacher') then
    raise exception 'not your student';
  end if;
  if act = 'reset' then
    if newpin !~ '^[0-9]{4}$' then raise exception 'bad pin'; end if;
    update students set pin_hash = crypt(newpin, gen_salt('bf')) where id = sid;
  elsif act = 'delete' then
    delete from students where id = sid;
  end if;
end $$;

create or replace function student_get(n text, p text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r int; o jsonb; lib int;
begin
  r := _sid(n, p);
  lib := _slib(r);
  select jsonb_build_object(
    'name', (select name from students where id = r),
    'role', (select role from students where id = r),
    'weak', (select weak from students where id = r),
    'classes', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'teacher', (select name from students where id = c.owner_id)) order by lower(c.name))
        from classes c join class_members cm on cm.class_id = c.id where cm.student_id = r), '[]'::jsonb),
    'results', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc)
        from (select kind, set_name, score, total, seconds, assignment_id, created_at
              from results where student_id = r order by created_at desc limit 60) x), '[]'::jsonb),
    'assignments', coalesce((select jsonb_agg(jsonb_build_object(
        'id', a.id, 'title', a.title, 'set_name', a.set_name, 'minutes', a.minutes, 'due', a.due,
        'class', (select name from classes where id = a.class_id),
        'mode', a.mode, 'goal', a.goal, 'target', a.target) || _adone(a, r)
        order by a.created_at desc) from assignments a
        where a.active and (exists (select 1 from class_members cm where cm.class_id = a.class_id and cm.student_id = r)
                            or (a.class_id is null and a.owner_id = lib))), '[]'::jsonb)
  ) into o;
  return o;
end $$;

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
        'weak', (select count(*) from jsonb_object_keys(s.weak)),
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

do $$ begin
  begin revoke execute on function teacher_assign(text, text, text, int, date) from public, anon, authenticated; exception when undefined_function then null; end;
  begin revoke execute on function teacher_assign2(text, text, text, int, date, int) from public, anon, authenticated; exception when undefined_function then null; end;
end $$;
grant execute on function save_sets(text, jsonb) to anon;
grant execute on function lib_get(text, text, int) to anon;
grant execute on function teacher_class(text, text, text, int, int) to anon;
grant execute on function student_join(text, text, text) to anon;
grant execute on function teacher_assign3(text, text, text, int, date, int, text, text, int) to anon;
grant execute on function teacher_end(text, int) to anon;
grant execute on function teacher_student(text, int, text, text) to anon;
grant execute on function student_get(text, text) to anon;
grant execute on function teacher_report(text) to anon;
