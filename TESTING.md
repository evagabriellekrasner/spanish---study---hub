# Study Hub: testing rules

**Standing rule:** every new feature or fix ships with a new test in `tests.html`, so the tests always cover everything the site does.

## How it works
- `tests/tests.html` is the source of the test page. It is never published (Netlify only publishes `site/`). `tests/build-checks.py` embeds it into `index.html` as a private page: open the live site with `#checks` on the end and enter the checks passcode (the site owner has it; only its SHA-256 hash is in the site).
- After any change to `tests/tests.html` or `site/index.html`, run `python3 tests/build-checks.py` before committing.
- It loads a sealed copy of `index.html`: no internet, blank in-memory storage, so it never touches real students, classes, or libraries.
- `node tests/run-tests.js` runs the same page headlessly (exits 1 on any failure).

## Adding a test
1. If the feature lives inside a closure in `index.html`, expose what the test needs on `window` (e.g. `window.SH_agree=agree`).
2. In `tests.html`, add a `suite("Plain-English name")` inside `run(w)` with `check(name, ok, detail)` or `eq(name, got, want)` calls. `w` is the site's window.
3. Prove the test can fail: break the feature in a throwaway copy and confirm the test goes red. Then run the full suite on the real file and confirm it's all green.
4. Run `python3 tests/build-checks.py` and `node tests/run-tests.js`, then push to `main` (Netlify deploys automatically).

## Answer key
`KEY` in `tests.html` holds every built-in verb in all 8 tenses, all checked by hand. When adding a verb to the built-in list, check its forms and add it to `KEY` (the "Built-in verb list" suite fails until you do).
