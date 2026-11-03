# Loro: problems to fix before scaling to a student body

Review of the repo as of commit `a5407ab`. I read the code and SQL, and checked the live site's response headers. I did not run attacks, load tests, or queries against the live database.

**Biggest gap:** login security. Anyone can guess a 4-digit PIN with unlimited tries, including a teacher's, and a teacher account can reach every student in that teacher's classes. Fix the "Fix first" section before adding more schools or classes.

## Fix first: security and student privacy

### 1. PINs can be guessed, and nothing slows it down
- Every student and teacher logs in with a name and a 4-digit PIN, so there are only 10,000 possibilities. I found no rate limit or lockout in the login checks (`_tctx` in `database/libraries.sql:33`). `_sid`, the student login check, isn't in the repo, so confirm it on the live database.
- Student usernames are predictable: animal + class tag, from a list of 50 animals (`database/animal-logins.sql`). Anyone with a class code can see which animals are taken, using `class_animals`.
- **Students can attack their teacher.** `student_get` gives students the teacher's account name. A student could try all 10,000 PINs from the browser console, probably in well under an hour. They would then control the gradebook, could reset student PINs, and could delete students or classes.
- The bcrypt hashes use the default low cost (`gen_salt('bf')`). With only 10,000 possible PINs, a database leak would expose all of them almost immediately.
- **Partly fixed:** teachers now use real passwords (8+ characters, letters and numbers) via `database/teacher-passwords.sql`. Lockouts were left out on purpose.
- **Fix:** move teachers to Supabase Auth or Google sign-in, with real passwords. Add attempt tracking and lockouts per account and per IP. Longer term, use school SSO for students as well.

### 2. PINs are kept in plain text in the browser and sent on every request
- `localStorage.pstu` holds the name and PIN (`site/index.html:1028`, `:1059`), and it stays there until the student logs out. On a shared Chromebook, the next person can read it or simply carry on as that student.
- There are no sessions, so every call re-sends the credentials and re-runs bcrypt.
- The login screen says the PIN is "scrambled" (`site/index.html:1282`), which is only true of the database copy.
- **Fix:** use short-lived session tokens from Supabase Auth or a signed session function. Never store the PIN. Add an idle timeout for shared devices.

### 3. Script injection through picture URLs, made worse by #2
- Picture sets put image URLs into HTML without escaping (`site/index.html:370, 376, 378, 380, 385, 432, 630, 875, 914, 1001`, and others).
- `save_sets` and `teacher_share` accept any JSON, and share codes pass that JSON from teacher to teacher. A crafted image value could run script for every student who opens the set, and that script could read their stored PIN. A compromised teacher account therefore reaches every student.
- `gtext()` also inserts `a.mode` without escaping at `site/index.html:1122`.
- GitHub Pages can't set security headers, and the site has no Content-Security-Policy.
- **Partly fixed:** picture links now go through `isrc()` (only `data:image/` or `https:`, escaped), and `gtext()` output is escaped. Still to do: Validate library JSON on the server. Add a CSP meta tag. Over time, replace `innerHTML` string building, which is used everywhere.

### 4. Students can write their own grades
- The browser does all the scoring, then calls `student_log` with any score, total and seconds (`database/fix-turn-in.sql`). One console call can record 100/100 or complete a timed goal.
- The server doesn't check that the student belongs to the assignment's class, or that the assignment is still active. A student can also log against another class's assignment, and `teacher_report` will list them in that assignment's progress.
- "You can't keep working after turning in" is only enforced in the browser. Timed tries use the browser's clock.
- **Fix:** add the class, active and turned-in checks and basic number limits now. If these results will count as real grades, the server has to issue the questions and score the answers. Otherwise, tell teachers it is a practice tool and that its numbers can be faked.

### 5. Hidden units and answers aren't really hidden
- "Who sees this unit" is only applied in the browser (`visOK`, `site/index.html:495`). `lib_get` sends the teacher's whole library to every student in the class.
- **Fix:** filter on the server by class, or tell teachers plainly that this setting only tidies the view.

### 6. Student privacy compliance is missing
Animal usernames are a good choice, but practice records from minors are probably still education records. Before a school rollout you will likely need:
- A privacy policy. The site only has a one-sentence note.
- A data-privacy agreement that districts can sign, plus FERPA, COPPA and state law review (for example NY Ed Law 2-d). Get a lawyer's or the district's opinion on these.
- A retention and deletion policy. Results are currently kept forever.
- A way to export or delete a student's data when asked. "Export my sets" only covers sets.
- Disclosure of third parties: Supabase, GitHub, Google Fonts (which sees student IP addresses), and cdnjs. Browser speech recognition may also send student voice to Google or Apple.
- ~~Device-local name labels (`plbl`) are stored unencrypted, so real names could be left on a shared teacher computer.~~ Fixed: name labels were removed.

### 7. The old Netlify copy still runs against the live database (fixed: script run, Netlify site deleted)
`netlify.toml` and `close-name-signup.sql` show that the frozen copy is still up and uses the old "type your name" sign-up. It won't receive any of these fixes, and it could collect real names unless `close-name-signup.sql` has been run. Take it down or redirect it, then run that script if it hasn't been run.

## Fix next: bugs that lose or corrupt data

### 8. Students on shared devices can get each other's weak spots
`logout()` removes `pstu` but not `pm`, the weak-spot data (`site/index.html:1067`). On the next login, `apply()` sees the leftover entries and pushes them to the new student's account (`:1051`). Teacher weak-spot reports then become wrong. This will be common with Chromebook carts. I found this by reading the code and haven't reproduced it.

### 9. A teacher's library can be overwritten
- `save_sets` replaces the entire library with no version check, so with two tabs or devices the last save wins.
- It's riskier than a normal save conflict: `verify()` writes the library back just to check the login (`site/index.html:967`). That happens on every teacher page load, so opening a stale device can undo a recent save.
- `save_sets` has no size limit, though `teacher_share` has an 8 MB one, and there is no version history.
- **Fix:** move sets to their own rows, or at least add a version check. Keep previous versions. Use a read-only login check.

### 10. Deleting is permanent and destroys records
- Deleting a class also deletes its student accounts and assignments, and the students' results if the `results` table cascades as `clear-student-accounts.sql` says it does.
- Teachers will do this at the end of the year, or by accident, and lose the gradebook.
- **Fix:** add archive and soft delete, with a recovery window.

### 11. Due dates and "Late" labels are wrong in US time zones
- `fd()` parses `2026-11-05` as midnight UTC, so US users see **Nov 4** (`site/index.html:1042`).
- The "Late" check compares a UTC date with the due date (`:1127`). Work turned in at 8 pm Eastern on the due date shows as late.
- The database uses server time and the browser uses local time, so choose one rule, such as a school time zone.

### 12. Work is lost when the network drops, and failed saves retry too fast
- During an assignment, a failed `student_log` puts the time back, so the check that runs every second tries again right away (`site/index.html:1070`, `:1084`). If the server struggles, every student adds about one request per second, each with a bcrypt check, which makes an outage worse.
- Unsent time and timed tries live only in memory or a toast message, so a reload loses them. School Wi-Fi will make this common.
- **Fix:** add a saved retry queue, retry delays that grow with jitter, and a visible "not saved" state.

### 13. Concurrent sign-ups may collide
Sign-up checks for the name and then inserts it, and a whole class will sign up at the same moment. No unique index on `lower(name)` appears in the repo, so two students may be able to create the same account. Confirm it exists on the live database. Also handle the conflict cleanly as "animal taken".

## Performance and capacity

### 14. The database may be missing indexes (check first)
The `students`, `results`, `assignments`, `sets` and `secrets` tables aren't defined in the repo, so I can't see their indexes. The repo adds none for the lookups that matter most. Check the live database for these and add any that are missing:
```sql
create unique index on students (lower(name));
create index on results (student_id, created_at desc);
create index on results (assignment_id, student_id);
create index on class_members (student_id);
create index on classes (owner_id);
create index on assignments (owner_id, created_at desc);
```

### 15. `teacher_report` will slow down as data grows
It loads everything in one call: all students, all weak spots, and per-student progress for every assignment including ended ones (`database/timed-goal.sql:50`). Those progress lookups repeat for each assignment and student. The site prefetches this report on the teacher home screen. Split it by class, page ended assignments, and store totals instead of recalculating them.

### 16. `results` grows quickly with no cleanup
Active assignments log a row about once a minute. As a rough estimate, 1,000 students × 20 minutes × 5 days × 36 weeks is **3.6 million rows a year**, before counting round results. Every write also runs bcrypt. Batch the time logs, roll up old data, and decide how long to keep raw rows.

### 17. Every page load is heavy
- `index.html` is **1.9 MB**. About 1.6 MB of that is 68 inline base64 images (line 200), and 61 KB is the test suite shipped to all users (line 1404).
- The live site's `max-age` is 600 seconds, and changing any line invalidates all of it.
- Every login also downloads the whole teacher library through `lib_get`, including any uploaded pictures as base64. This can be slow on a school network or at the start of class.
- **Fix:** move images to separate cached files or Supabase Storage. Remove the tests from the production page. Load libraries by set, and keep pictures out of the JSON.

### 18. Check hosting limits
I couldn't see your Supabase plan. Before rollout, confirm the following:
- Connection, database and bandwidth limits, tested with a class-start burst (for example, 300 logins in a minute).
- Free Supabase projects pause when idle, which could take the site down over summer, and the free plan doesn't include managed backups.
- GitHub Pages has a soft bandwidth limit and restrictions on commercial use, so check them if this becomes paid.
- School content filters allow `github.io` and `supabase.co`. These are commonly blocked or need allowlisting.

## Built for one teacher, not a school

### 19. Missing account and school features
- **No admin role.** Nobody at a school can manage teachers, see across classes, or take over when a teacher leaves. Co-teaching was removed.
- **No account recovery.** Teachers have no forgot-PIN path, and I found no way to change a PIN. Recovery means someone editing the database by hand.
- **One shared teacher code** controls all teacher sign-ups (`secrets.pass`). Any existing teacher login also passes that check. It can't identify who was invited, and leaking it is a school-wide problem. Use per-school or single-use invites.
- **No rostering.** There's no Google Classroom, Clever or ClassLink sync. Teachers must map animal usernames to real students by hand, per device, using local labels.
- **No gradebook export** to a CSV or a school system. Teachers will expect this.
- **No school or district structure.** There's one global namespace, so teacher names and class tags must be unique across all schools.

### 20. The class model will break in normal use
- A student can only be in one class. Joining another silently removes them from the first (`student_join`, `database/libraries.sql:129`).
- Each class is capped at 50 students because there are 50 animals.
- Anyone with a code can create accounts until every animal is taken. Codes never rotate or expire, so a leaked code can block a class.
- There's no school year or term concept. Usernames are tied to the class, so a student's history doesn't carry from Spanish 1 to Spanish 2.

## Keeping it maintainable

### 21. Database changes are unsafe and can't be rebuilt
- **The base schema isn't in the repo.** The core tables, `_sid` and `student_save_weak` exist only in the live database, so you can't rebuild it if it's lost or create a test copy.
- Scripts are run by hand, with no record of the order or of what has been applied.
- **Some "safe to run again" labels are wrong.** Re-running `weak-spots.sql` after `timed-goal.sql` removes `words` from the report, and `libraries.sql` replaces the newer `teacher_class`, which removes class tags and animal cleanup. Older scripts also overwrite `_adone`, and `sharing.sql` empties `lib_members`.
- The site's error messages tell students to "ask your teacher to run fix-turn-in.sql", which shows front-end and database changes aren't released together.
- **Fix:** run `supabase db dump` now. Move to numbered migrations with the Supabase CLI, and use a separate staging project. Confirm that automated backups exist, and test a restore.

### 22. Nothing stops a bad deploy
- `.github/workflows/pages.yml` publishes every push to `main` without running tests, and goes live for all students in about a minute.
- There's no `package.json`, so the Playwright test dependency isn't pinned.
- The tests block all network access, so **no SQL, permission or login logic is tested**. That's where most of the serious problems above are.
- **Fix:** run tests in CI before deploying. Add database tests against a local Supabase, including tests that try to access another teacher's data. Add a staging site, and avoid deploying during school hours.

### 23. You can't see failures
I found no error reporting, global error handler, uptime monitoring or usage analytics. Many failures are swallowed by empty `catch` blocks. If login breaks in first period, you'll hear about it from a teacher. Add privacy-reviewed error reporting, uptime and database alerts, and a status or support contact.

### 24. The single large file will get harder to change safely
- About 250 KB of hand-written JS, CSS and HTML sits in one file, with extremely long lines. New behavior is often added by wrapping old functions: `saveS` is defined or wrapped 7 times, so behavior depends on load order.
- There's leftover code as well, such as `if(!false)` (line 270) and a backup block that only runs under `window.claude` (line 922).
- This also makes #3 hard to fix everywhere. Split the file into modules with a small build step, and do it before adding the school features.
- `README.md`, `TESTING.md` and the code still use older names and hosts (Study Hub, Netlify).

### 25. Accessibility falls short of school requirements
Schools often require WCAG 2.1 AA and a VPAT.
- The page is marked `lang="es"` although the interface is mostly English, so screen readers will mispronounce it. Spanish terms should be tagged individually.
- There are no `aria-live` regions, so correct/wrong feedback, timers and toasts aren't announced.
- There's no `tabindex` anywhere, so clickable cards may not be reachable by keyboard. Most generated images have no meaningful alt text.
- There's no `prefers-reduced-motion` support, for example for the confetti.
- Timed assignments have no extra-time option per student, which IEP and 504 plans may require.

## Suggested order

| Phase | Items | Goal |
| --- | --- | --- |
| 1. Now, before any more students | 1 (rate limits and lockouts), 3, 7, 8, 11, 21 (schema dump and backups) | Close the worst holes and make the data recoverable |
| 2. Before a school pilot | 1 and 2 (real auth), 4, 5, 9, 10, 12, 13, 14, 22, 23 | Trustworthy data, safe deploys, visible failures |
| 3. Before a school-wide rollout | 6, 15, 16, 17, 18, 19, 20, 25 | Compliance, capacity, school features |
| 4. Ongoing | 24 | Keep it changeable |

## Check on the live database
These affect the priorities above, but I can't see them from the repo:
1. Does `_sid` have any attempt limiting?
2. Do the indexes in #14 exist, including unique `lower(name)`?
3. Are RLS policies on the base tables correct, and is `_sid` or any other internal function still executable by `anon`? Postgres grants execute to everyone by default.
4. Has `close-name-signup.sql` been run?
5. Which Supabase plan is it on, and do backups exist?
