# vault-observer

A lightweight background daemon for Linux that watches your Obsidian vault and automatically commits and pushes changes to GitHub on a fixed interval. Built to survive power outages — the maximum data loss is always equal to the configured interval, regardless of how long you have been editing.

---

## How It Works

The observer runs silently as a systemd service from startup. Every 3 minutes (configurable), it wakes up, checks if anything changed in your vault, and if so — commits and pushes to GitHub. It then goes back to sleep.

```
boot → observer starts → sleeps 3 min → checks for changes → commits + pushes → sleeps again → repeat
```

The maximum data loss in any power cut scenario is exactly one interval. If you have been editing for 2 hours straight, the last checkpoint was at most 3 minutes ago.

---

## Project Structure

```
vault-observer/
├── config.env            ← THE ONLY FILE YOU EVER NEED TO EDIT
├── vault-observer.sh     ← main observer script (do not edit directly)
├── vault-observer.service← systemd service template (do not edit directly)
├── install.sh            ← installer (run this after every config change)
├── README.md
└── CONTEXT.md
```

**The workflow is simple:** edit `config.env` → run `./install.sh` → done. The installer reads your config and wires everything up automatically.

---

## Requirements

- Ubuntu 24.04 or any systemd-based Linux
- `git` installed
- A GitHub account with credentials configured in the terminal
- Your Obsidian vault folder already linked to a GitHub remote

---

## Pre-Installation

**1. Install git**

```bash
sudo apt install git
```

**2. Verify your vault has a GitHub remote**

```bash
git -C ~/obsidian-vault remote -v
```

Expected output:

```
origin  git@github.com:your-username/obsidian-vault.git (fetch)
origin  git@github.com:your-username/obsidian-vault.git (push)
```

If blank, add it:

```bash
git -C ~/obsidian-vault remote add origin git@github.com:YOUR_USERNAME/YOUR_REPO.git
```

**3. Verify SSH authentication**

```bash
ssh -T git@github.com
```

Expected response:

```
Hi your-username! You've successfully authenticated, but GitHub does not provide shell access.
```

The "does not provide shell access" part is always there and always normal.

**4. Make sure the terminal can push without being asked for credentials**

```bash
git config --global credential.helper store
git -C ~/obsidian-vault push origin main
```

If it asks for a password, use a GitHub Personal Access Token — not your GitHub account password. Generate one at: GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token → check `repo` → set expiration to `No expiration`. Enter this token as the password. After one successful push, credentials are saved permanently.

---

## Installation

**Step 1 — Clone the repo**

```bash
git clone <this-repo>
cd <this-repo>
```

**Step 2 — Edit `config.env`**

Open `config.env` and set your vault path and preferred interval:

```bash
nano config.env
```

The only line most people need to change:

```
VAULT_DIR="$HOME/obsidian-vault"
```

**Step 3 — Run the installer**

```bash
chmod +x install.sh vault-observer.sh
./install.sh
```

The installer shows you your settings and asks for confirmation before doing anything. It then installs the script, generates the service file with your config baked in, and starts the observer.

---

## Changing Any Setting Later

This is the key workflow. You never edit the installed files directly.

```
1. Open config.env in your cloned repo
2. Make your change
3. Run ./install.sh again
```

The installer stops the old service, reinstalls everything with the new config, and restarts. One command does it all.

---

## Configuration Reference

All settings live in `config.env`. Here is what each one does:

| Setting               | Default                            | What it controls                        |
| --------------------- | ---------------------------------- | --------------------------------------- |
| `VAULT_DIR`           | `$HOME/obsidian-vault`             | Path to your Obsidian vault             |
| `INTERVAL_SECONDS`    | `180`                              | How often to check and commit (seconds) |
| `GIT_BRANCH`          | `main`                             | Which branch to push to                 |
| `GIT_REMOTE`          | `origin`                           | Remote name (almost always origin)      |
| `COMMIT_AUTHOR_NAME`  | `Vault Observer`                   | Name shown in git log                   |
| `COMMIT_AUTHOR_EMAIL` | `observer@local`                   | Email shown in git log                  |
| `LOG_FILE`            | `~/.local/logs/vault-observer.log` | Where the log is written                |
| `MAX_LOG_LINES`       | `500`                              | Log size before rotation                |

---

## Post-Installation Verification

**Check the service is running:**

```bash
systemctl --user status vault-observer
```

Look for `Active: active (running)`.

**Watch the observer live:**

```bash
tail -f ~/.local/logs/vault-observer.log
```

A healthy log looks like this:

```
[25-04-2026 18:17:02] [INFO] Vault Observer started (PID 17686)
[25-04-2026 18:17:02] [INFO] Watching  : /home/sakif/obsidian-vault
[25-04-2026 18:17:02] [INFO] Interval  : every 180s
[25-04-2026 18:17:02] [INFO] Max loss  : 180s of work
[25-04-2026 18:20:02] [INFO] Checkpoint — scanning for changes...
[25-04-2026 18:20:02] [INFO] Committed 1 file(s) — "Observer: Pushed at 25-04-2026 06:20 PM"
[25-04-2026 18:20:04] [INFO] Pushed successfully to origin/main
[25-04-2026 18:23:04] [INFO] Checkpoint — scanning for changes...
[25-04-2026 18:23:04] [INFO] No changes detected — going back to sleep.
```

**Trigger a manual test:** Create or edit any file inside your vault and wait one full interval. The commit will appear on GitHub with the message `Observer: Pushed at DD-MM-YYYY HH:MM AM/PM`.

---

## Service Control

```bash
# Status
systemctl --user status vault-observer

# Stop
systemctl --user stop vault-observer

# Start
systemctl --user start vault-observer

# Restart
systemctl --user restart vault-observer

# Live journal log
journalctl --user -u vault-observer -f

# View recent git history in vault
git -C ~/obsidian-vault log --oneline -10
```

---

## Recovering a File After a Power Cut

```bash
git -C ~/obsidian-vault checkout HEAD -- "path/to/your-note.md"
```

This restores the file to exactly how it was at the last Observer commit.

---

## Removing a Folder From Git Tracking

If a folder is already pushed to GitHub and you want to remove it (e.g. `.obsidian/`):

```bash
# 1. Add to gitignore
echo ".obsidian/" >> ~/obsidian-vault/.gitignore

# 2. Stop tracking it (leaves your local files untouched)
git -C ~/obsidian-vault rm -r --cached .obsidian/

# 3. Commit and push the removal
git -C ~/obsidian-vault add .gitignore
git -C ~/obsidian-vault commit -m "chore: remove .obsidian from tracking"
git -C ~/obsidian-vault push origin main
```

The folder disappears from GitHub. Your local files are untouched. The observer will never touch it again.

---

## Troubleshooting

**Push failed (exit 128)**

The terminal has not authenticated with GitHub yet.

```bash
git config --global credential.helper store
git -C ~/obsidian-vault push origin main
```

Enter your username and Personal Access Token when prompted. After this one push, all future pushes are silent.

**Push failed (exit 1)**

Run the push manually to read the actual error:

```bash
git -C ~/obsidian-vault push origin main
```

**"No remote configured" in the log**

```bash
git -C ~/obsidian-vault remote add origin git@github.com:YOUR_USERNAME/YOUR_REPO.git
```

**Service not starting after reboot**

```bash
journalctl --user -u vault-observer -f
```

Most common cause: the vault path in `config.env` does not match where your vault actually is.

**Changes not being pushed after editing config**

Make sure you ran `./install.sh` after editing `config.env`. Editing `config.env` alone does nothing — the installer is what applies the changes.

---

## Installed File Locations

| File            | Location                                        |
| --------------- | ----------------------------------------------- |
| Observer script | `~/.local/bin/vault-observer.sh`                |
| Service file    | `~/.config/systemd/user/vault-observer.service` |
| Log file        | `~/.local/logs/vault-observer.log`              |

Do not edit these directly. Edit `config.env` in your cloned repo and re-run `./install.sh`.
