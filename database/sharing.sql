-- Share sets between teachers with a share code, and remove co-teaching.
-- Run once in the Supabase SQL Editor (safe to run again).
create table if not exists set_shares (
  code text primary key,
  owner_id int not null references students(id) on delete cascade,
  title text not null,
  data jsonb not null,
  created_at timestamptz default now()
);
alter table set_shares enable row level security;

delete from lib_members;

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
  end if;
  return null;
end $$;

create or replace function teacher_share(pw text, act text, code text, d jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c int[]; k text; i int; s set_shares;
begin
  c := _tctx(pw);
  if act = 'create' then
    if jsonb_typeof(d->'sets') <> 'array' or jsonb_array_length(d->'sets') < 1 then raise exception 'nothing to share'; end if;
    if octet_length(d::text) > 8000000 then raise exception 'too big'; end if;
    loop
      k := '';
      for i in 1..8 loop k := k || substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random() * 31)::int, 1); end loop;
      exit when not exists (select 1 from set_shares where set_shares.code = k);
    end loop;
    insert into set_shares (code, owner_id, title, data)
      values (k, c[1], left(coalesce(nullif(trim(d->>'title'), ''), 'Shared sets'), 120), d);
    return jsonb_build_object('code', k);
  elsif act = 'get' then
    select * into s from set_shares where set_shares.code = upper(regexp_replace(coalesce(teacher_share.code, ''), '[^A-Za-z0-9]', '', 'g'));
    if s.code is null then raise exception 'bad share'; end if;
    return jsonb_build_object('title', s.title, 'from', (select name from students where id = s.owner_id),
                              'unit', s.data->'unit', 'sets', s.data->'sets');
  elsif act = 'list' then
    return coalesce((select jsonb_agg(jsonb_build_object('code', x.code, 'title', x.title,
             'count', jsonb_array_length(x.data->'sets'), 'created', x.created_at) order by x.created_at desc)
           from set_shares x where x.owner_id = c[1]), '[]'::jsonb);
  elsif act = 'delete' then
    delete from set_shares where set_shares.code = teacher_share.code and owner_id = c[1];
  end if;
  return null;
end $$;

grant execute on function teacher_class(text, text, text, int, int) to anon;
grant execute on function teacher_share(text, text, text, jsonb) to anon;
