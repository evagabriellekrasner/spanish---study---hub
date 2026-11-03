-- Turns off the old "type your name" student sign-up, so new student accounts can only be animal usernames.
-- Run in the Supabase SQL Editor AFTER animal-logins.sql, once everyone uses the new link
-- (the old Netlify copy used the old sign-up). Already run, and the Netlify copy is deleted. Safe to run again.
create or replace function student_signup(n text, p text) returns int
language plpgsql security definer set search_path = public, extensions as $$
begin
  raise exception 'use class code';
end $$;
