# First-time git setup for the Chharizard repo

Run these once, in the Chharizard folder, before your first commit.

## Step 1 — Create the repo on GitHub

1. Go to https://github.com/new
2. **Owner**: ChharithOeun
3. **Name**: `Chharizard`
4. **Description**: `FFXI multibox HUD + automation suite for Windower 4`
5. **Public**
6. **Do NOT** initialize with README / .gitignore / license (we have our own)
7. Click "Create repository"

## Step 2 — Initialize locally

Open a terminal in this folder (`Chharizard/`) and run:

```bat
git init
git branch -M main

REM Override author for THIS repo so real name never gets committed
git config user.name "Chharbot"
git config user.email "ChharithOeun@users.noreply.github.com"

git add .
git commit -m "Initial commit: Chharizard v5.0.0 monorepo skeleton"
git remote add origin https://github.com/ChharithOeun/Chharizard.git
git push -u origin main
```

## Step 3 — Verify no real name leaked

After push, on GitHub:

- Open any file → **Blame** → confirm commits show "Chharbot", not real name
- Repo home → **Insights** → **Contributors** → confirm only "Chharbot" appears

If a real name shows anywhere, run:

```bat
git filter-repo --mailmap mailmap.txt
git push --force origin main
```

with `mailmap.txt` containing:
```
Chharbot <ChharithOeun@users.noreply.github.com> <YourOldEmail@example.com>
Chharbot <ChharithOeun@users.noreply.github.com> Chharith <realname@example.com>
```

## Step 4 — Set up branch protection (optional but recommended)

GitHub → repo Settings → Branches → Add rule for `main`:
- Require pull request reviews before merging
- Require status checks (once CI is added)

Prevents accidental force-pushes that could re-leak history.

## Step 5 — First release

Once addons are ported into the repo:

```bat
git tag -a v5.0.0 -m "v5.0.0 — Chharbar rebrand to Chharizard umbrella"
git push origin v5.0.0
```

Then on GitHub: **Releases → Draft new release** → pick the tag → upload `Chharizard-v5.0.0.zip` (containing all addons) → publish.

Chharizard.exe's auto-updater is now able to find this release.
