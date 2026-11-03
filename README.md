# 🦜 Loro

**A Spanish practice site for students and teachers.** Students practice vocabulary and verb conjugations by typing real answers. Teachers make classes, send assignments with clear goals, and see who's done and what each class keeps missing.

**Live:** https://spanishstudysite.github.io/ · Built by Eva Krasner

---

## Why Loro
- **Typing, not guessing.** Students type every answer, so they actually learn the spelling and the accents.
- **Private by design.** Students never enter their real name. They sign up as an animal (like `koalaab3`) with a 4-digit PIN.
- **Built for a real class.** Assignments, goals, turn-in, a gradebook, and weak spots, all in one place.
- **Free and simple.** It's one web page with no app to install, and it works on school laptops and phones.

## Features

### For students
- **Vocabulary practice** with built-in sets by unit, plus sets their teacher adds
- **Verb conjugation practice** across 8 tenses, including present, preterite, imperfect, future, conditional, present perfect and progressive forms, with clear rules pages (regular endings, stem changers, -car/-gar/-zar, irregular stems, and more)
- **Accent buttons** for á é í ó ú ñ ü, and an optional lenient mode that ignores accents
- **Practice tests** and **timed rounds**
- **My weak spots:** the words they keep missing, saved to their account so they can practice them again
- **Assignments** from their class, with a live goal tracker and a **Turn in** button
- **Themes** to choose the site's colors
- Works without an account for quick practice. Logging in saves progress to any device.

### For teachers
- **Classes** with a join code. Each class gets a tag (initials + period) that becomes part of every student's username.
- **Assignments** with three goal types:
  - practice for N minutes
  - complete N terms at a minimum %
  - a timed goal, like "40 words in 8 minutes at 80%"
- Assignments can be edited after they go out, and deleted one at a time, all ended ones at once, or all of them.
- **Gradebook and activity:** see who turned in work, their scores, and each student's full history.
- **Weak spots** for each student and for each class.
- **Animal usernames only:** Loro never stores real student names, not even on your computer. Keep your own list of which student is "koalaab3" in your school gradebook or on paper.
- **Your own library** of units and sets. You can share sets with another teacher by share code.

## Privacy
- Student accounts store only an **animal username, a scrambled (bcrypt) PIN, class membership, and practice results**. There are no names, emails, or birthdays.
- The browser never reads database tables directly. Every request goes through a database function that checks the username and PIN, or the teacher's login, first.
- Teachers' name labels for students live only on the teacher's own device.

## How it's built
| Part | What it uses |
| --- | --- |
| Front end | One static page, `site/index.html`, in plain HTML, CSS, and JavaScript. No framework, no build step. |
| Hosting | GitHub Pages publishes the `site/` folder (`.github/workflows/pages.yml`). Every push to `main` is live in about a minute. |
| Database | Supabase (PostgreSQL) with row-level security and `security definer` functions. PINs are bcrypt-hashed. |
| Tests | 950+ checks in `tests/tests.html`, run headlessly with Playwright and also available on a private `#checks` page |

The old Netlify copy is frozen (`netlify.toml` skips all builds).

## Folders
| Folder | What's in it |
| --- | --- |
| `site/` | The live website (the only thing that gets published) |
| `tests/` | The test page, the headless test runner, and the script that builds the private `#checks` page into the site |
| `database/` | SQL scripts that set up and update the Supabase database |
| `docs/` | A one-pager for teachers and the school |

## Run it locally
```bash
# open the site
python3 -m http.server -d site 8000     # then visit http://localhost:8000

# run the tests (needs Node and Playwright)
node tests/run-tests.js
```

## Making a change
1. Edit `site/index.html`, and add a test for the change in `tests/tests.html` (see `TESTING.md`). **Every new feature ships with a test.**
2. Run `python3 tests/build-checks.py` to embed the latest tests into the site's private `#checks` page.
3. Run `node tests/run-tests.js`. Everything must pass.
4. Push to `main`, and GitHub Pages publishes it.

**Database changes:** add a new `.sql` file in `database/` and run it in the Supabase SQL Editor. Scripts are written to be safe to run more than once.

See `CLAUDE.md` for coding conventions and `PRD.md` for the product plan.
