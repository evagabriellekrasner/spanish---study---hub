-- Lets teachers edit an assignment after it's sent out. Students keep their progress.
-- Run once in the Supabase SQL Editor (safe to run again).
create or replace function teacher_assign_edit(pw text, aid int, t text, m int, d date, cid int, md text, gl text, tg int, w int) returns void
language plpgsql security definer set search_path = public as $$
declare c int[];
begin
  c := _tctx(pw);
  if not exists (select 1 from assignments where id = aid and owner_id = c[2]) then raise exception 'bad assignment'; end if;
  if gl not in ('minutes', 'terms', 'timed') then raise exception 'bad goal'; end if;
  if gl = 'minutes' and (m < 1 or m > 240) then raise exception 'bad minutes'; end if;
  if gl = 'terms' and (m < 1 or m > 1000 or tg < 1 or tg > 100) then raise exception 'bad terms'; end if;
  if gl = 'timed' and (m < 1 or m > 60 or w < 1 or w > 1000 or tg < 1 or tg > 100) then raise exception 'bad timed'; end if;
  if cid is not null and not exists (select 1 from classes where id = cid and owner_id = c[2]) then raise exception 'bad class'; end if;
  update assignments set title = left(t, 120), minutes = m, due = d, class_id = cid, mode = nullif(left(md, 20), ''), goal = gl,
    target = case when gl in ('terms', 'timed') then tg end, words = case when gl = 'timed' then w end
  where id = aid and owner_id = c[2];
end $$;
grant execute on function teacher_assign_edit(text, int, text, int, date, int, text, text, int, int) to anon;
