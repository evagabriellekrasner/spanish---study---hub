# Owner tools: checks, backups and error emails

Everything here emails you through GitHub when something needs your attention. Students and teachers never see any of it.

| What | When | You get an email when |
| --- | --- | --- |
| **Checks before publishing** (`pages.yml`) | Every change to `main` | A check fails. The site then stays on the last good version. |
| **Keep database awake** (`keep-awake.yml`) | Mondays and Thursdays | The database doesn't answer |
| **Weekly backup** (`backup.yml`) | Sundays, about 1 AM | The backup fails |
| **Daily error check** (`error-check.yml`) | Every morning, about 6 AM | Someone hit an error in the last 24 hours |

GitHub sends these to the email on your GitHub account. To check: GitHub > Settings > Notifications > Actions > "Only notify for failed workflows" should be on.

## One-time setup

1. **Run `database/error-log.sql`** in the Supabase SQL Editor. The result shows an **owner token**, and it's only shown once. Copy it.
2. **Open the repo's secrets page:** https://github.com/spanishstudysite/spanishstudysite.github.io/settings/secrets/actions and click **New repository secret** three times:
   - `OWNER_TOKEN`: the owner token from step 1.
   - `DATABASE_URL`: in Supabase, click **Connect** (top of the dashboard), choose **Session pooler**, and copy the URI. Replace `[YOUR-PASSWORD]` with your database password. If you don't know it, reset it under Project Settings > Database.
   - `BACKUP_PASSPHRASE`: make up a long passphrase, like four random words. **Save it in a safe place.** Without it, nobody (including you) can open the backups.
3. **Test both:** go to the **Actions** tab, then open **Weekly database backup** and click **Run workflow**. Do the same for **Daily error check**. Both should turn green.

Secrets are never visible in the code, the logs, or to anyone else, even though the repo is public.

## Getting data back from a backup

1. Go to **Actions > Weekly database backup**, open a run, and download the file under **Artifacts** (a zip containing `loro-backup-DATE.sql.gz.gpg`).
2. Unlock it on a computer with `gpg` and `psql`:
   ```bash
   gpg -d loro-backup-DATE.sql.gz.gpg | gunzip > loro-backup.sql
   ```
3. Ask Claude (or another developer) to help restore only what's needed. Never run the whole file on the live database without checking first, because it would replace newer data.
