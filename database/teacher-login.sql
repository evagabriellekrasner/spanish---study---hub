-- Teacher accounts unlock editing by logging in (no passcode prompt). Run once in the Supabase SQL Editor.
create or replace function _teach(pw text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare j jsonb;
begin
  if pw is not distinct from (select v from secrets where k = 'pass') then return; end if;
  begin j := pw::jsonb; exception when others then j := null; end;
  if j is not null and jsonb_typeof(j) = 'object' and exists (
       select 1 from students
       where lower(name) = lower(trim(j->>'n')) and role = 'teacher' and pin_hash = crypt(j->>'p', pin_hash)) then
    return;
  end if;
  raise exception 'wrong passcode';
end $$;
revoke all on function _teach(text) from public, anon, authenticated;

drop function if exists save_sets(text, jsonb);
drop function if exists save_sets(text, json);
drop function if exists save_sets(text, text);
create function save_sets(pw text, d jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _teach(pw);
  update sets set data = d where id = 1;
  if not found then insert into sets (id, data) values (1, d); end if;
end $$;
grant execute on function save_sets(text, jsonb) to anon;
