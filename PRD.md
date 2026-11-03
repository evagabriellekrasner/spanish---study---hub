# Loro: Product Requirements Document

| | |
| --- | --- |
| **Product** | Loro (formerly Spanish Study Hub / Spanish Study Site) |
| **Owner** | Eva Krasner |
| **Live** | https://spanishstudysite.github.io/ |
| **Status** | Live, in a pilot with the school's Spanish department |
| **Last updated** | November 2026 |

---

## 1. Summary
Loro is a free web app where high school Spanish students practice vocabulary and verb conjugations by typing, and their teachers assign practice, set goals, and see results. It is built to be usable in a public school: students never give personal information, it runs in any browser, and there's nothing to install.

## 2. Problem
- Popular study tools are built around multiple choice and matching, so students can pass without being able to spell a word or conjugate a verb.
- Many tools ask students for names, emails, or Google sign-in, which runs into school student-privacy rules (for example, Illinois SOPPA) and needs district approval.
- Teachers want to know who actually practiced, for how long, and which words the class keeps missing, without grading worksheets by hand.

## 3. Goals
1. Students build real recall by **typing** answers, including the accents.
2. **Zero student personal information** is collected or stored.
3. A teacher can go from "new class" to "assignment sent" in under 5 minutes.
4. Teachers see completion and weak spots at a glance.
5. It stays free to run and simple to maintain: one static page plus a hosted database.

### Non-goals (for now)
- Speaking, listening, or pronunciation practice
- Native mobile apps (the website works on phones and can be added to the home screen)
- Logins with Google or Clever accounts, or links to school gradebooks
- Languages other than Spanish
- Ads, payments, or collecting data for any purpose besides practice

## 4. Users
| User | Needs |
| --- | --- |
| **Student** (grades 9–12) | Quick practice that's clear about what's right and wrong, knowing what's due, seeing progress, and not having to remember a complicated login |
| **Teacher** | Making classes, sending assignments with a clear bar for "done", seeing who finished, finding weak spots, and using their own vocab lists |
| **Department chair / school** | Assurance that no student personal info is stored, and that it's safe to approve |

## 5. Requirements

### 5.1 Accounts and privacy (must have)
- **Student sign-up** needs a **class code**. The student picks an available animal, and the username becomes `animal + class tag` (e.g. `koalaab3`). The student then sets a 4-digit PIN.
  - Every class can use the same 50 animals. An animal shows as taken only if someone **in that same class** already has it.
  - Sign-up screens show no example names.
- **Student data stored:** username, a bcrypt-hashed PIN, class membership, practice results, and weak spots. Nothing else.
- **Teacher accounts** use a name and password. Creating one needs the department's teacher code.
- **Private labels:** a teacher can label an animal username with a real name. The label is stored only in that teacher's browser.
- All database access goes through server functions that check the username and PIN, or the teacher's login. The browser never reads tables directly.
- Deleting a class also deletes the animal-only student accounts in it.

### 5.2 Student practice (must have)
- Vocabulary sets organized by unit. Built-in sets, plus sets the student's teacher adds, including class-only units.
- Verb conjugation in 8 tenses, with an answer key checked by hand for every built-in verb, and rules pages for the tricky patterns.
- Typed answers, on-screen accent buttons, and an optional lenient mode for accents.
- Practice tests and timed rounds.
- "My weak spots" list, saved to the account.
- Quick practice without an account.
- A greeting that uses the student's animal (for example, "Hi, Koala 🐨").

### 5.3 Assignments (must have)
- Teacher creates an assignment for a class with a due date and one of these goals:
  - practice for N minutes
  - complete N terms at ≥ X%
  - timed: N words in M minutes at ≥ X%
- The student sees a live goal tracker, a "Goal met!" message, and a **Turn in** button with a confirmation step.
- Teacher can edit an assignment after sending it (students keep their progress), and can delete one, all ended ones, or all of them. Deleting keeps students' practice history.

### 5.4 Teacher insight (must have)
- Gradebook showing turned-in work and scores for each assignment
- Each student's full activity history
- Weak spots for each student and for each class

### 5.5 Teacher library (should have)
- Each teacher has a separate library of units and sets.
- Teachers can share sets with other teachers by share code.
- A content checker catches mistakes in new sets before students see them.

### 5.6 Look and feel (should have)
- Brand: **Loro**, with a cute blue sparkle parrot logo. The default theme is Ocean Slate blue, and other themes are available.
- Works well on Chromebooks, laptops, and phones. The login screen scrolls on short screens.
- Can be installed to a phone home screen with the parrot icon.

## 6. Quality requirements
- **Tests:** every feature has automated tests (950+ checks). Every new feature or fix adds a test. The full suite must pass before any push.
- **Privacy:** no student personal info in the database, the code, or the screens. No secrets in the public repo.
- **Speed:** the site is one static page served from a CDN, with no build step.
- **Reliability:** if a database update hasn't been run yet, the site shows a friendly message instead of breaking.
- **Access:** the site must load on the school network. GitHub Pages was chosen after the old host was blocked.

## 7. Success metrics
| Metric | Proposed target |
| --- | --- |
| Chair or school approval for classroom use | Approved |
| Teachers actively using it | 2+ teachers this school year |
| Assignment completion rate | ≥ 75% of students turn in each assignment |
| Weekly active students during the pilot | ≥ 60% of enrolled students |
| Student personal info stored | 0 records |

## 8. Launch checklist and open items
- [x] Move hosting to GitHub Pages (the school blocked the old host)
- [x] Animal usernames, with the class code required for students
- [x] Clear old student accounts that had real names
- [x] Teachers can delete assignments
- [x] Rename to Loro, with the new parrot logo
- [ ] Confirm the new link loads on the school network
- [ ] Change the teacher code before real students join
- [ ] Run `database/close-name-signup.sql` once every teacher is on the new link
- [ ] Update the one-pager in `docs/` with the Loro name and new link

## 9. Ideas for later
- **"Forgot username" help:** a student enters the class code, then their animal, to find their username. The teacher resets the PIN.
- **"Who's who" screen:** one page where teachers can label all their students at once.
- **Class leaderboard by animal**, which is fun and still anonymous.
- **Spaced review** that brings weak spots back automatically over the following days.
- **Export the gradebook** to a spreadsheet.
