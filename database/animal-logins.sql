-- Animal logins: students sign up as animal + teacher initials + period (e.g. pandaem7), so no names are stored.
-- Run once in the Supabase SQL Editor.

-- Each class gets a tag: the teacher's initials + period, e.g. "em7". Tags are unique so usernames never clash.
alter table classes add column if not exists tag text;
create unique index if not exists classes_tag_key on classes (lower(tag)) where tag is not null;

create or replace function _animals() returns text[]
language sql immutable as $$
  select array['panda','koala','otter','fox','bunny','kitten','puppy','penguin','owl','tiger',
               'lion','bear','sloth','llama','dolphin','whale','turtle','frog','duck','deer',
               'hedgehog','raccoon','seal','zebra','giraffe','monkey','hamster','chick','bee','ladybug',
               'butterfly','parrot','flamingo','octopus','shark','wolf','moose','beaver','squirrel','mouse',
               'cow','pig','lamb','horse','camel','hippo','elephant','unicorn','dragon','snail']
$$;

-- Teacher class actions, now with "tag" (set initials + period) and "tags" (list them).
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
    -- animal usernames only make sense in their class, so those student accounts go with it
    delete from students s where s.role = 'student'
      and s.id in (select student_id from class_members where class_id = (select id from classes where id = cid and owner_id = c[2]))
      and not exists (select 1 from class_members m where m.student_id = s.id and m.class_id <> cid);
    delete from classes where id = cid and owner_id = c[2];
  elsif act = 'remove' then
    delete from class_members where student_id = sid
      and class_id = (select id from classes where id = cid and owner_id = c[2]);
  elsif act = 'tag' then
    k := lower(regexp_replace(coalesce(nm, ''), '[^A-Za-z0-9]', '', 'g'));
    if k !~ '^[a-z]{2,3}[0-9]{1,2}$' then raise exception 'bad tag'; end if;
    if not exists (select 1 from classes where id = cid and owner_id = c[2]) then raise exception 'bad class'; end if;
    if exists (select 1 from classes where lower(tag) = k and id <> cid) then raise exception 'tag taken'; end if;
    if exists (select 1 from class_members cm join students s on s.id = cm.student_id
               where cm.class_id = cid and s.role = 'student' and s.name ~ '^[a-z]+[a-z]{2,3}[0-9]{1,2}$')
       and (select tag from classes where id = cid) is distinct from k then raise exception 'tag locked'; end if;
    update classes set tag = k where id = cid;
    return to_jsonb(k);
  elsif act = 'tags' then
    return coalesce((select jsonb_object_agg(id::text, tag) from classes where owner_id = c[2] and tag is not null), '{}'::jsonb);
  end if;
  return null;
end $$;

-- What a student sees after typing a class code: the class tag and which animals are taken.
create or replace function class_animals(code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c classes;
begin
  select * into c from classes where classes.code = upper(trim(class_animals.code));
  if c.id is null then raise exception 'bad code'; end if;
  if c.tag is null then raise exception 'no tag'; end if;
  return jsonb_build_object('tag', c.tag, 'class', c.name,
    'taken', coalesce((select jsonb_agg(a) from unnest(_animals()) a
                       where exists (select 1 from students s join class_members m on m.student_id = s.id
                                     where m.class_id = c.id and lower(s.name) = a || lower(c.tag))), '[]'::jsonb));
end $$;

-- Student sign-up with no name: the username is built from the animal and the class tag.
create or replace function student_signup_animal(code text, animal text, p text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare c classes; n text; r int;
begin
  select * into c from classes where classes.code = upper(trim(student_signup_animal.code));
  if c.id is null then raise exception 'bad code'; end if;
  if c.tag is null then raise exception 'no tag'; end if;
  animal := lower(trim(animal));
  if not (animal = any(_animals())) then raise exception 'bad animal'; end if;
  if p !~ '^[0-9]{4}$' then raise exception 'bad pin'; end if;
  n := animal || lower(c.tag);
  if exists (select 1 from students s join class_members m on m.student_id = s.id
             where m.class_id = c.id and lower(s.name) = n) then raise exception 'animal taken'; end if;
  -- an old account with this username that isn't in any class (its class was deleted) is cleared out
  delete from students s where lower(s.name) = n and s.role = 'student'
    and not exists (select 1 from class_members m where m.student_id = s.id);
  if exists (select 1 from students where lower(name) = n) then raise exception 'animal taken'; end if;
  insert into students (name, pin_hash) values (n, crypt(p, gen_salt('bf'))) returning id into r;
  insert into class_members (class_id, student_id) values (c.id, r);
  return n;
end $$;

revoke all on function _animals() from public, anon, authenticated;
grant execute on function teacher_class(text, text, text, int, int) to anon;
grant execute on function class_animals(text) to anon;
grant execute on function student_signup_animal(text, text, text) to anon;
