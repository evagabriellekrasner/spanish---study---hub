-- Turns off the old "type your name" student sign-up, so new student accounts can only be animal usernames.
-- Run in the Supabase SQL Editor AFTER animal-logins.sql, once everyone uses the new link
-- (the frozen Netlify copy still uses the old sign-up).
create or replace function student_signup(n text, p text) returns int
language plpgsql security definer set search_path = public, extensions as $$
begin
  raise exception 'use class code';
end $$;
