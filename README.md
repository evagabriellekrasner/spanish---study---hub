# Spanish Study Hub

A Spanish practice site for students and teachers. Students practice vocabulary and verb conjugations by typing. Teachers create classes, send assignments with goals (for example, "20 terms at 80%" or "40 words in 8 minutes at 80%"), see turned-in work in a gradebook, and see each class's weak spots.

Built by Eva Krasner. Live at https://spanishwesbitedhs11.netlify.app/

## How it's built
- **Front end:** one static page, `site/index.html`, in plain HTML, CSS, and JavaScript. There is no framework and no build step.
- **Hosting:** Netlify publishes only the `site/` folder (see `netlify.toml`). Every push to `main` goes live automatically.
- **Database:** Supabase (PostgreSQL). The browser only calls SQL functions that check a name and PIN (or teacher login) first, and the tables use row-level security. PINs are stored as bcrypt hashes.

## Folders
| Folder | What's in it |
| --- | --- |
| `site/` | The live website (the only thing Netlify publishes) |
| `tests/` | The test page, the headless test runner, and the script that builds the private `#checks` page into the site |
| `database/` | SQL scripts that set up and update the Supabase database |

## Making a change
1. Edit `site/index.html`, and add a test for the change in `tests/tests.html` (see `TESTING.md`).
2. Run `python3 tests/build-checks.py` to embed the latest tests into the site's private `#checks` page.
3. Run `node tests/run-tests.js`. Everything must pass.
4. Push to `main`, and Netlify deploys it.
