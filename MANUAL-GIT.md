# Manual git push — copy-paste path (no .bat needed)

If `INIT.bat` won't run for any reason, do this instead.

## Step 1 — Open cmd.exe in this folder

Two ways:

**Option A:** In File Explorer, navigate to the `Chharizard` folder. Click the address bar, delete what's there, type `cmd`, press Enter. A cmd window opens in that folder.

**Option B:** Start menu → type `cmd` → Enter. Then manually:
```bat
cd /d "C:\path\to\your\Chharizard"
```
(replace the path with wherever the folder actually is on your PC)

## Step 2 — Verify git is installed

```bat
git --version
```

If you get "not recognized as an internal or external command", install Git for Windows:
https://git-scm.com/download/win — then **close and reopen cmd** and try again.

## Step 3 — Run these commands one by one

Copy each block, paste into cmd, press Enter. Watch the output after each.

```bat
git init
```

```bat
git branch -M main
```

```bat
git config user.name "Chharbot"
```

```bat
git config user.email "ChharithOeun@users.noreply.github.com"
```

```bat
git add .
```

```bat
git commit -m "v5.0.0 - Chharizard monorepo skeleton"
```

```bat
git remote add origin https://github.com/ChharithOeun/Chharizard.git
```

```bat
git push -u origin main
```

## Step 4 — When it asks for credentials

- **Username:** `ChharithOeun`
- **Password:** paste a Personal Access Token, NOT your GitHub password.
  - Get one at: https://github.com/settings/tokens
  - Click "Generate new token (classic)"
  - Give it a name like "Chharizard push"
  - Check the **repo** scope
  - Click Generate
  - Copy the token immediately (you can't view it again)
  - Paste it as the password

## Troubleshooting

### "repository not found"
The empty repo doesn't exist yet on GitHub. Create it at:
- https://github.com/new
- Name: `Chharizard`
- Public
- **UNCHECK** "Add a README file", "Add .gitignore", "Choose a license" — we already have all three

### "remote origin already exists"
That's fine. Skip to `git push -u origin main`.

### "updates were rejected"
Someone (probably a checkbox on the "new repo" page) initialized the repo with something. Run:
```bat
git pull --rebase origin main
git push -u origin main
```

### Push succeeds but no files show up
Refresh https://github.com/ChharithOeun/Chharizard — badges may take a minute to render.

### Credential prompt never appears / hangs
Windows may be using an old cached credential. Reset it:
- Control Panel → User Accounts → Credential Manager → Windows Credentials
- Find any entry starting with `git:https://github.com`
- Delete it
- Rerun `git push -u origin main` — you'll be prompted fresh

## After first successful push

Future updates:
```bat
git add .
git commit -m "your change description"
git push
```
