-- Lets teachers delete assignments (one, all ended ones, or all of them).
-- Students' practice history is kept; it just stops counting toward the deleted assignment.
-- Run once in the Supabase SQL Editor.
create or replace function teacher_assign_delete(pw text, aid int, which text) returns int
language plpgsql security definer set search_path = public as $$
declare c int[]; ids int[];
begin
  c := _tctx(pw);
  select coalesce(array_agg(id), '{}') into ids from assignments
   where owner_id = c[2]
     and case which when 'one' then id = aid when 'ended' then not active when 'all' then true else false end;
  update results set assignment_id = null where assignment_id = any(ids);
  delete from assignments where id = any(ids);
  return coalesce(array_length(ids, 1), 0);
end $$;

grant execute on function teacher_assign_delete(text, int, text) to anon;
