-- Terms goal now counts terms completed (answered), not terms right.
create or replace function _adone(a assignments, sid int) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'words', a.words,
    'submitted', max(r.created_at) filter (where r.kind = 'submit'),
    'done_seconds', coalesce(sum(r.seconds), 0),
    'rounds', count(*) filter (where r.total > 0),
    'best', coalesce(max(round(100.0 * r.score / r.total)) filter (where r.total > 0), 0),
    'right', coalesce(sum(r.score) filter (where r.total > 0), 0),
    'answered', coalesce(sum(r.total) filter (where r.total > 0), 0),
    'tries', count(*) filter (where r.kind = 'timed'),
    'tbest', (select jsonb_build_object('n', x.total, 'r', x.score) from results x
              where x.assignment_id = a.id and x.student_id = sid and x.kind = 'timed' and x.total > 0
              order by (100 * x.score >= coalesce(a.target, 0) * x.total) desc, x.total desc, x.score desc limit 1),
    'done', case a.goal
      when 'finish' then count(*) filter (where r.total > 0) >= 1
      when 'score' then coalesce(max(round(100.0 * r.score / r.total)) filter (where r.total > 0), 0) >= coalesce(a.target, 0)
      when 'terms' then coalesce(sum(r.total) filter (where r.total > 0), 0) >= a.minutes
        and coalesce(sum(r.total) filter (where r.total > 0), 0) > 0
        and 100.0 * sum(r.score) filter (where r.total > 0) / sum(r.total) filter (where r.total > 0) >= coalesce(a.target, 0)
      when 'timed' then count(*) filter (where r.kind = 'timed' and r.total >= coalesce(a.words, 1)
        and 100 * r.score >= coalesce(a.target, 0) * r.total) > 0
      else coalesce(sum(r.seconds), 0) >= a.minutes * 60 end)
  from results r where r.assignment_id = a.id and r.student_id = sid
$$;
revoke all on function _adone(assignments, int) from public, anon, authenticated;
