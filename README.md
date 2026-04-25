# vault-observer

A lightweight background daemon for Linux that watches your Obsidian vault and automatically commits and pushes changes to GitHub on a fixed interval. Built to survive power outages — the maximum data loss is always equal to the configured interval, regardless of how long you have been editing.

---

## How It Works

The observer runs silently as a systemd service from startup. Every 3 minutes (configurable), it wakes up, checks if anything changed in your vault, and if so — commits and pushes to GitHub. It then goes back to sleep. No event listeners, no complex logic. Just a reliable checkpoint on a fixed schedule.

```txt
boot → observer starts → sleeps 3 min → checks for changes → commits + pushes → sleeps again → repeat
```

The maximum data loss in any power cut scenario is exactly one interval. If you have been editing for 2 hours straight, the last checkpoint was at most 3 minutes ago.

---

## Requirements

- Ubuntu 24.04 (or any systemd-based Linux)
- `git` installed
- A GitHub account with SSH authentication configured
- Your Obsidian vault folder already initialized as a git repo with a remote pointing to GitHub

---

## Pre-Installation

Before running the installer, make sure these are in order.

**1. Install dependencies**

```bash
sudo apt install git
```

**2. Verify your vault is a git repo with a GitHub remote**

```bash
git -C ~/obsidian-vault remote -v
```

You should see something like:

```bash
origin  git@github.com:your-username/obsidian-vault.git (fetch)
origin  git@github.com:your-username/obsidian-vault.git (push)
```

If this shows nothing, add the remote manually:

```bash
git -C ~/obsidian-vault remote add origin git@github.com:YOUR_USERNAME/YOUR_REPO.git
```

**3. Verify SSH authentication with GitHub**

```bash
ssh -T git@github.com
```

Expected response:

```bash
Hi your-username! You've successfully authenticated, but GitHub does not provide shell access.
```

The second part of that message ("does not provide shell access") is normal. If you see this, SSH is working.

**4. Make sure the terminal can push without being asked for credentials**

```bash
git config --global credential.helper store
git -C ~/obsidian-vault push origin main
```

If it asks for a password here, use a GitHub Personal Access Token — not your GitHub account password. Generate one at: GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token. Check the `repo` scope and set expiration to `No expiration`. Use this token as the password. After one successful push, credentials are saved permanently and the observer handles everything silently from here.

---

## Installation

```bash
# Clone the repo
git clone <this-repo>
cd <this-repo>

# Make scripts executable
chmod +x install.sh vault-observer.sh

# Run the installer
./install.sh
```

The installer will ask two questions:

- Full path to your Obsidian vault (e.g. `/home/sakif/obsidian-vault`)
- Checkpoint interval in seconds (recommended: `180` for 3 minutes)

It then copies the script, registers the systemd service, and starts the observer automatically.

---

## Post-Installation Verification

**Check that the service is running:**

```bash
systemctl --user status vault-observer
```

Look for `Active: active (running)`.

**Watch the observer live:**

```bash
tail -f ~/.local/logs/vault-observer.log
```

This streams every action the observer takes in real time. A healthy log looks like this:

```bash
[24-04-2026 18:17:02] [INFO] Vault Observer started (PID 17686)
[24-04-2026 18:17:02] [INFO] Watching  : /home/sakif/obsidian-vault
[24-04-2026 18:17:02] [INFO] Interval  : every 180s
[24-04-2026 18:17:02] [INFO] Max loss  : 180s of work
[24-04-2026 18:40:43] [INFO] Checkpoint — scanning for changes...
[24-04-2026 18:40:43] [INFO] Committed 1 file(s) — "Observer: Pushed at 24-04-2026 @06:40 PM"
[24-04-2026 18:40:46] [INFO] Pushed successfully to origin/main
```

**Trigger a manual test:**

Create a file inside your vault, wait the full interval, and watch the log. You should see a commit and push appear automatically.

**Confirm on GitHub:**

Go to your GitHub repo. The commit will appear with the message `Observer: Pushed at DD-MM-YYYY @HH:MM AM/PM`.

---

## Service Control

```bash
# Stop the observer
systemctl --user stop vault-observer

# Start it again
systemctl --user start vault-observer

# Restart (use this after any config changes)
systemctl --user restart vault-observer

# View live system logs (alternative to the log file)
journalctl --user -u vault-observer -f

# View recent git history in your vault
git -C ~/obsidian-vault log --oneline -10
```

---

## Recovering a File After a Power Cut

If a file gets wiped or corrupted during a power outage, restore the last committed version:

```bash
git -C ~/obsidian-vault checkout HEAD -- "path/to/your-note.md"
```

This pulls the exact state from the last Observer commit and overwrites the damaged file.

---

## Configuration Reference

All configurable values live in two places depending on what you want to change.

### Changing the interval

Open the service file:

```bash
nano ~/.config/systemd/user/vault-observer.service
```

Find and edit:

```bash
Environment=INTERVAL_SECONDS=180
```

Then reload:

```bash
systemctl --user daemon-reload
systemctl --user restart vault-observer
```

### Changing the vault path

Same file, same process. Edit:

```bash
Environment=VAULT_DIR=/home/sakif/obsidian-vault
```

Also update this line in the same file to match:

```bash
ReadWritePaths=/home/sakif/obsidian-vault /home/sakif/.local
```

Then reload and restart.

### Changing the commit message format

Open the main script:

```bash
nano ~/.local/bin/vault-observer.sh
```

Find this line inside the `commit_changes` function:

```bash
local msg="Observer: Pushed at $now"
```

Change the text however you like. The `$now` variable is a formatted timestamp. Keep it or remove it — your call.

Then restart the service:

```bash
systemctl --user restart vault-observer
```

No daemon-reload needed when you only edit the script, not the service file.

### Changing which files are ignored

The observer commits everything git tracks. To exclude files from commits, add them to your vault's `.gitignore`:

```bash
nano ~/obsidian-vault/.gitignore
```

Example entries:

```txt
.obsidian/workspace.json
.obsidian/workspace-mobile.json
*.tmp
```

### Renaming the observer script

If you rename `vault-observer.sh`, you must also update the service file to match. Open:

```bash
nano ~/.config/systemd/user/vault-observer.service
```

Find:

```bash
ExecStart=%h/.local/bin/vault-observer.sh
```

Change it to the new name. Then:

```bash
systemctl --user daemon-reload
systemctl --user restart vault-observer
```

---

## Troubleshooting

### Push failed (exit 128)

The observer can commit but cannot push. Most likely cause: the terminal has not authenticated with GitHub yet.

```bash
git -C ~/obsidian-vault push origin main
```

Run this manually. If it asks for credentials, enter your GitHub username and Personal Access Token (not your password). After one successful manual push, all future pushes from the observer work silently.

### Push failed (exit 1) repeatedly

Run the push manually and read the error:

```bash
git -C ~/obsidian-vault push origin main
```

Common causes: wrong branch name (`main` vs `master`), no remote configured, or expired credentials.

### "No remote configured" in the log

```bash
git -C ~/obsidian-vault remote add origin git@github.com:YOUR_USERNAME/YOUR_REPO.git
```

### Service not starting after reboot

```bash
journalctl --user -u vault-observer -f
```

Read the error. Common cause: the vault path in the service file doesn't match where your vault actually is.

### SSH authentication fails

```bash
ssh-keygen -t ed25519 -C "your@email.com"
cat ~/.ssh/id_ed25519.pub
```

Copy the output and add it at: GitHub → Settings → SSH and GPG keys → New SSH key.

---

## Files

| File                     | Location after install                          | Purpose         |
| ------------------------ | ----------------------------------------------- | --------------- |
| `vault-observer.sh`      | `~/.local/bin/vault-observer.sh`                | The main script |
| `vault-observer.service` | `~/.config/systemd/user/vault-observer.service` | systemd config  |
| `install.sh`             | run once, not kept                              | Setup wizard    |
| Log file                 | `~/.local/logs/vault-observer.log`              | Runtime log     |
