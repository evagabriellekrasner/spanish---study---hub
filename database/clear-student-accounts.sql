-- Deletes every STUDENT account (and, through the existing cascades, their practice results and class memberships),
-- so no real student names stay in the database. Teacher accounts, classes, assignments, units, and sets are kept.
-- Run once in the Supabase SQL Editor. This cannot be undone.
delete from students where role = 'student';

-- Check: this should show only teacher accounts.
select id, name, role from students order by id;
