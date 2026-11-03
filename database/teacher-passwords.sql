-- Teacher passwords: teachers use a real password (8+ characters, letters and numbers) instead of a 4-digit PIN.
-- Run once in the Supabase SQL Editor. Safe to run again.
-- Students keep their 4-digit PINs. Existing teachers keep working: the site asks them to pick a password
-- the next time they log in with their old PIN.

-- Is this a strong enough teacher password? 8 to 72 characters, at least one letter and one number.
create or replace function _goodpw(p text) returns boolean
language sql immutable as $$
  select coalesce(length(p) between 8 and 72 and p ~ '[A-Za-z]' and p ~ '[0-9]', false)
$$;
revoke all on function _goodpw(text) from public, anon, authenticated;

-- New teacher accounts need a password instead of a 4-digit PIN.
create or replace function teacher_signup(n text, p text, pw text) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare r int;
begin
  perform _teach(pw);
  n := trim(n);
  if length(n) < 1 or length(n) > 30 then raise exception 'bad name'; end if;
  if not _goodpw(p) then raise exception 'weak password'; end if;
  if exists (select 1 from students where lower(name) = lower(n)) then raise exception 'name taken'; end if;
  insert into students (name, pin_hash, role) values (n, crypt(p, gen_salt('bf', 10)), 'teacher') returning id into r;
  return r;
end $$;
grant execute on function teacher_signup(text, text, text) to anon;

-- A teacher changes their PIN or password to a new password. Needs the current one.
create or replace function teacher_set_password(n text, p text, np text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare t int;
begin
  select id into t from students
    where lower(name) = lower(trim(n)) and role = 'teacher' and pin_hash = crypt(p, pin_hash);
  if t is null then raise exception 'bad login'; end if;
  if not _goodpw(np) then raise exception 'weak password'; end if;
  update students set pin_hash = crypt(np, gen_salt('bf', 10)) where id = t;
end $$;
grant execute on function teacher_set_password(text, text, text) to anon;

-- Heads-up check: the student login check (_sid) isn't in the repo. If it only accepts 4 digits,
-- teachers can't log in with a password, and this prints a notice. Send a screenshot if you see it.
do $$
begin
  if exists (select 1 from pg_proc where proname = '_sid')
     and (select pg_get_functiondef(oid) from pg_proc where proname = '_sid' limit 1) ~ '\{4\}' then
    raise notice '_sid only accepts 4-digit PINs. Teachers will need a fix before passwords work.';
  end if;
end $$;
