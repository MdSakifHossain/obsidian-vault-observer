# vault-observer — Session Context
### Feed this file to Claude if context is lost. It contains the full history of decisions, problems, and solutions from the original build session.

---

## Who Is This For

**User:** MdSakifHossain (GitHub username confirmed via SSH auth output)
**OS:** Ubuntu 24.04, shell: zsh
**Hardware:** Ryzen 7 7700, 32GB DDR5, 1TB NVMe Gen 4
**Editor:** Obsidian (markdown vault), also uses VSCode
**Skill level:** Knows JavaScript at a decent level. No bash/shell scripting knowledge. Knows basic git: `git add .`, `git commit -m`, `git push`, basic remote setup. Recently switched to Linux. Treat all explanations with JS analogies. Never assume Linux or bash knowledge.

---

## The Problem

Frequent power outages (load shedding — scheduled power cuts common in Bangladesh). During outages, Obsidian's atomic write process gets interrupted, resulting in 0-byte files or wiped note content. A UPS is not currently viable due to budget.

**Goal:** A background process that automatically commits and pushes the Obsidian vault to GitHub at regular intervals so power cuts result in a maximum data loss of one interval, not the entire file.

---

## Version History

### V1 — Event-Driven with inotify (deprecated)

Used `inotifywait` to listen for filesystem events. On any file change, started a 3-minute debounce timer. When vault was quiet for 3 full minutes, committed and pushed.

**Fatal flaw discovered by user:** If editing continuously for 13 minutes and power cuts just before the cooldown completes, you lose all 13 minutes. The user independently identified this as a real problem — and they were correct. This is not a misunderstanding.

### V2 — Polling Model (working but no config file)

Replaced inotify with a simple `while true; sleep; check; commit; push` loop. Fixed the data loss problem — maximum loss is always exactly one interval regardless of editing duration. `inotify-tools` dependency removed.

**Remaining problem:** Settings were split between `vault-observer.service` (for systemd) and `vault-observer.sh` (for defaults). To change something like the commit message format, user had to edit the installed file at `~/.local/bin/vault-observer.sh` directly, not the cloned repo. User correctly identified this as wrong — they wanted to edit the cloned repo and re-run the installer to apply changes.

Also discovered during V2: the commit message used `@` before the time (`Observer: Pushed at 25-04-2026 @06:34 PM`). On GitHub, the `@` symbol turns into a mention link pointing to `https://github.com/06` which looks broken. User asked to remove the `@`. Final chosen format: `Observer: Pushed at 25-04-2026 06:34 PM` using `date '+%d-%m-%Y %I:%M %p'`.

### V3 — Polling Model with Central Config (current)

Added `config.env` as the single source of truth. The installer reads `config.env`, fills placeholders in the service template, and installs everything. User never needs to touch any installed file. Workflow is: edit `config.env` → run `./install.sh` → done.

---

## Current File Structure

```
vault-observer/
├── config.env              ← only file the user ever edits
├── vault-observer.sh       ← main script, reads env vars set by systemd
├── vault-observer.service  ← template with __PLACEHOLDERS__ filled by installer
├── install.sh              ← reads config.env, fills placeholders, installs everything
├── README.md
└── CONTEXT.md              ← this file
```

---

## How config.env Works

`install.sh` sources `config.env` to load all variables, then uses `sed` to replace `__PLACEHOLDER__` strings in `vault-observer.service` with the actual values before writing the final service file to `~/.config/systemd/user/`. The observer script reads values from environment variables set by systemd — so it always uses whatever was baked in at install time.

When the user wants to change any setting:
1. Edit `config.env` in the cloned repo
2. Run `./install.sh`
3. Installer stops old service, reinstalls script and service file, restarts

---

## Architecture — Function by Function

### vault-observer.sh

**check_deps()** — verifies git is installed. Exits with helpful message if not.

**check_vault()** — verifies vault directory exists and has `.git`. Auto-inits git repo if missing.

**commit_changes()** — runs `git add -A`, checks staged diff, commits with timestamped message. Returns 0 if committed, 1 if nothing to commit. Uses `-A` flag specifically to capture deletions too (not just additions and modifications).

**push_changes()** — checks remote exists first, then pushes with 30s timeout. Push failure is non-fatal — local commit already succeeded. Will retry next cycle.

**cleanup()** — trap for SIGTERM/SIGINT/SIGHUP. Runs final commit+push before dying. This means `systemctl --user stop vault-observer` triggers a final checkpoint before shutdown.

**main()** — core loop: `while true; sleep; commit if changed; push if committed; done`

### vault-observer.service

Template file. Contains `__PLACEHOLDER__` strings that `install.sh` replaces with real values via `sed`. After install, the real file lives at `~/.config/systemd/user/vault-observer.service`.

Key resource limits:
- `CPUQuota=5%` — hard cap
- `MemoryMax=64M` — hard cap (typical use ~18MB)
- `Nice=15` — low priority
- `IOSchedulingClass=idle` — lowest IO priority

**Critical rule:** After editing the service file, always run `systemctl --user daemon-reload`. After editing only the `.sh` script, daemon-reload is not needed — just restart.

### install.sh

1. Checks for `config.env` in same directory — exits if missing
2. Sources `config.env` to load all variables
3. Expands `$HOME` in paths manually (shell substitution doesn't always work inside sourced files)
4. Shows loaded settings and asks for confirmation
5. Checks/installs git if missing
6. Checks vault directory exists, creates if not
7. Stops existing service if running
8. Copies `vault-observer.sh` to `~/.local/bin/` and makes executable
9. Uses `sed` to fill all `__PLACEHOLDER__` values in service template, writes result to `~/.config/systemd/user/vault-observer.service`
10. Runs `loginctl enable-linger` so service survives logout
11. Runs daemon-reload, enable, start
12. Confirms service is active

---

## Problems Encountered — Full Chronology

### Problem 1: Push failed (exit 128) on first commit

**Cause:** Installer created a fresh git repo in the vault directory (because it had no `.git` folder). Fresh repos have no remote configured. The SSH test the user ran earlier was against a different directory.

**Fix:**
```bash
git -C ~/obsidian-vault remote add origin git@github.com:MdSakifHossain/REPO.git
```

### Problem 2: Terminal asked for credentials when pushing manually

**Cause:** VSCode has its own credential helper (GNOME keyring integration). Terminal git uses a separate credential system. They are independent.

**Fix:**
```bash
git config --global credential.helper store
git -C ~/obsidian-vault push origin main
```

Enter username and Personal Access Token once. Stored permanently in `~/.git-credentials`. All future pushes silent.

**Important:** GitHub no longer accepts account passwords for Git operations over HTTPS. Must use a Personal Access Token. Generate at: GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token → check `repo` → set `No expiration`.

### Problem 3: Commit message `@` symbol became a broken GitHub link

**Cause:** GitHub interprets `@` in commit messages as a user mention. `@06` pointed to `https://github.com/06`.

**Original format:** `date '+%d-%m-%Y @%I:%M %p'`
**Fixed format:** `date '+%d-%m-%Y %I:%M %p'`
**Result:** `Observer: Pushed at 25-04-2026 06:34 PM`

Appears in two places in `vault-observer.sh` — once in `commit_changes()` and once in `check_vault()` for the initial commit message.

### Problem 4: Editing installed files directly instead of the cloned repo

**Cause:** V1 and V2 had no single config file. To change settings, user had to edit `~/.local/bin/vault-observer.sh` directly, which is the installed copy — not the source repo. This meant the cloned repo and the running installation could get out of sync.

**Fix:** V3 introduced `config.env`. All settings live there. Running `./install.sh` always applies the current config to the installation. The installed files are now treated as build artifacts, not source files.

### Problem 5: Removing .obsidian from GitHub tracking

**User question:** Does adding `.obsidian/` to `.gitignore` remove it from GitHub if it's already there?

**Answer:** No. `.gitignore` only prevents untracked files from being tracked. Files already tracked continue to be tracked even if added to `.gitignore`. Must use `git rm -r --cached .obsidian/` to stop tracking without deleting local files.

**Full fix sequence:**
```bash
echo ".obsidian/" >> ~/obsidian-vault/.gitignore
git -C ~/obsidian-vault rm -r --cached .obsidian/
git -C ~/obsidian-vault add .gitignore
git -C ~/obsidian-vault commit -m "chore: remove .obsidian from tracking"
git -C ~/obsidian-vault push origin main
```

---

## Key Conceptual Explanations

### Polling vs event-driven — why polling wins here

Event-driven (debounce): timer resets on every file change. During continuous editing, timer never completes until you stop. 13 minutes of editing + power cut before cooldown = 13 minutes lost.

Polling: wakes on fixed schedule regardless of activity. 13 minutes of editing = at most one interval lost. Correct model for data safety as the primary concern.

### git add -A vs git add .

`git add .` stages new and modified files only.
`git add -A` stages new, modified, AND deleted files.
The observer uses `-A` specifically so deletions are committed too. If you delete a note, that deletion propagates to GitHub.

### What systemd is

Linux's process manager. Analogous to PM2 in Node. The `.service` file tells systemd what to run, when to start it, how to restart on failure, and what resource limits to apply. `systemctl --user` manages services in the current user's scope without sudo.

### What loginctl enable-linger does

By default, user systemd services stop when the user logs out. Linger keeps them running even with no active session.

### VSCode vs terminal credentials

VSCode integrates with the OS keychain silently. Terminal git uses whatever `credential.helper` is configured globally. Setting `credential.helper store` makes terminal git save credentials to `~/.git-credentials` after first use. Independent systems — fixing one does not fix the other.

### SSH "does not provide shell access"

Always appears in the response to `ssh -T git@github.com`. Normal. GitHub is not a shell server. The meaningful part is `You've successfully authenticated`.

### gitignore only works on untracked files

Files already committed to git remain tracked even if added to `.gitignore`. Must use `git rm --cached` to untrack them first. `--cached` means remove from git's index only — local files on disk are untouched.

---

## Current State

- V3 installed and running
- SSH auth confirmed working for MdSakifHossain
- GitHub remote confirmed on vault
- Credentials stored via credential.helper store
- Commit message format: `Observer: Pushed at 25-04-2026 06:34 PM`
- `.obsidian/` removed from tracking (user intended to do this)
- config.env established as single source of truth
- Workflow confirmed: edit config.env → ./install.sh → done

---

## User's Mental Model — JS Analogies That Worked

| Bash/Linux concept | JS equivalent used |
|---|---|
| systemd service | PM2 config / Docker Compose service |
| `vault-observer.sh` | `server.js` |
| `install.sh` | `npm create vite@latest` |
| `config.env` | `.env` file |
| polling loop | `while(true) { await sleep(); check(); }` |
| `git add -A` | staging everything including deletions |
| `git diff --cached` | checking if staging area has anything |
| `credential.helper store` | saving auth token to disk |
| `__PLACEHOLDER__` in service template | template literals / string interpolation |
| `sed` replacing placeholders | `.replace()` on a string |

User asks precise questions, catches real design flaws, and reasons well from first principles. Do not oversimplify. Explain tradeoffs honestly. When in doubt, use a JS analogy first.
