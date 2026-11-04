-- Private error log. When something breaks on a student's or teacher's screen, the site saves the error
-- message here (never a username, PIN or anything personal). A daily GitHub check emails the owner if
-- there were any errors. Run once in the Supabase SQL Editor. Safe to run again.
--
-- The first time you run it, the result at the bottom shows an OWNER TOKEN. Copy it into GitHub as the
-- secret OWNER_TOKEN. It's only shown once. To make a new one later, run the last line (commented out).

create table if not exists app_errors (
  id bigserial primary key,
  at timestamptz not null default now(),
  msg text not null,
  place text
);
alter table app_errors enable row level security;
create index if not exists app_errors_at on app_errors (at);

create table if not exists owner_secret (
  id int primary key default 1 check (id = 1),
  token_hash text not null
);
alter table owner_secret enable row level security;

-- The site calls this when something breaks. Anyone can call it, so it keeps itself small:
-- short messages only, at most 300 new rows an hour, and anything older than 60 days is removed.
create or replace function log_error(m text, w text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(trim(m), '') = '' then return; end if;
  if (select count(*) from app_errors where at > now() - interval '1 hour') >= 300 then return; end if;
  insert into app_errors (msg, place) values (left(m, 300), left(coalesce(w, ''), 60));
  delete from app_errors where at < now() - interval '60 days';
end $$;
grant execute on function log_error(text, text) to anon;

-- The daily GitHub check calls this with the owner token. It returns the last day's errors, grouped.
create or replace function owner_errors(tok text, hours int default 24) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  select token_hash into h from owner_secret where id = 1;
  if h is null or tok is null or crypt(tok, h) <> h then raise exception 'wrong token'; end if;
  return coalesce((select jsonb_agg(x order by x.times desc) from (
    select msg, place, count(*) as times, max(at) as last_seen
    from app_errors where at > now() - make_interval(hours => least(greatest(hours, 1), 24 * 60))
    group by msg, place) x), '[]'::jsonb);
end $$;
grant execute on function owner_errors(text, int) to anon;

-- Make the owner token the first time only, and show it once.
create or replace function _owner_new_token() returns text
language plpgsql security definer set search_path = public, extensions as $$
declare t text := encode(gen_random_bytes(18), 'hex');
begin
  insert into owner_secret (id, token_hash) values (1, crypt(t, gen_salt('bf', 8)))
  on conflict (id) do update set token_hash = excluded.token_hash;
  return t;
end $$;
revoke all on function _owner_new_token() from public, anon, authenticated;

select case when exists (select 1 from owner_secret)
  then 'Already set up. (To make a new token, run the last line of this script.)'
  else 'OWNER TOKEN (copy into GitHub as OWNER_TOKEN): ' || _owner_new_token() end as result;

-- select 'NEW OWNER TOKEN: ' || _owner_new_token();
