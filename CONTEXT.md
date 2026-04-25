# vault-observer — Session Report

Feed this file to Claude if context is lost. It contains the full history of decisions, problems, and solutions from the original build session.

---

## Who Is This For

**User:** MdSakifHossain (GitHub username confirmed via SSH auth output)
**OS:** Ubuntu 24.04, shell: zsh
**Hardware:** Ryzen 7 7700, 32GB DDR5, 1TB NVMe Gen 4
**Editor:** Obsidian (markdown vault), also uses VSCode
**Skill level:** Knows JavaScript at a decent level. No bash/shell scripting knowledge. Recently switched to Linux. Treat explanations accordingly — use JS analogies, avoid jargon without explanation.

---

## The Problem That Started Everything

Frequent power outages (load shedding — a scheduled power cut common in Bangladesh). During outages, Obsidian's atomic write process gets interrupted mid-write, resulting in 0-byte files or completely wiped note content. A UPS is not currently a viable solution due to budget constraints.

**Goal:** A background process that automatically commits and pushes the Obsidian vault to GitHub at regular intervals so that power cuts result in a maximum data loss of one interval, not the entire file.

---

## What Was Built — Version History

### V1 — Event-Driven Model (inotify + debounce)

**How it worked:** Used `inotifywait` (from `inotify-tools` package) to listen for filesystem events. When a file changed, started a 3-minute cooldown timer. Every new change reset the timer. When the vault was quiet for 3 full minutes, it committed and pushed.

**Files:**

- `vault-observer.sh` — main watcher script
- `vault-observer.service` — systemd user service unit
- `install.sh` — interactive installer

**Problem discovered by user:** If you edit continuously for 13 minutes and power cuts just before the 3-minute idle period completes, you lose all 13 minutes of work. The cooldown only starts after you stop editing. This is a real and valid concern, not an imaginary one.

**User's own model (which they described correctly):** Wake up on a fixed schedule, check for changes, commit and push if found, go back to sleep, repeat. The user independently invented the polling pattern.

### V2 — Polling Model (current, recommended)

**How it works:** No inotify, no event listeners. A simple `while true` loop that sleeps for the configured interval, wakes up, runs `git add -A` and checks if anything changed, commits and pushes if so, then sleeps again.

**Key guarantee:** Maximum data loss = interval length. Always. Even during continuous editing sessions.

**JS pseudocode equivalent:**

```js
while (true) {
  await sleep(INTERVAL_SECONDS * 1000);
  const hasChanges = await git.diff();
  if (hasChanges) {
    await git.add();
    await git.commit(`Observer: Pushed at ${timestamp}`);
    await git.push("origin", "main");
  }
}
```

**What changed from V1 to V2:**

- `inotify-tools` dependency removed entirely — only `git` needed now
- Entire inotify/debounce system replaced with `sleep` + `git diff` loop
- Config variable renamed from `COOLDOWN_SECONDS` to `INTERVAL_SECONDS`
- `vault-observer.service` and `install.sh` unchanged structurally

---

## Architecture — File by File

### `vault-observer.sh`

The main worker. Analogous to `server.js` in a Node project.

**Key functions:**

`check_deps()` — verifies `git` is installed. Crashes with a helpful message if not.

`check_vault()` — verifies the vault directory exists and has a `.git` folder. If no git repo found, runs `git init` automatically (one-time setup).

`commit_changes()` — runs `git add -A`, checks if anything is staged, commits with a timestamped message. Returns exit code 0 if committed, 1 if nothing to commit.

`push_changes()` — checks if a remote exists first (warns and skips gracefully if not). Runs `git push origin main` with a 30-second timeout. Push failure is non-fatal — the local commit already succeeded, data is safe. Will retry on next cycle.

`cleanup()` — trap for SIGTERM/SIGINT/SIGHUP. Runs a final commit+push before the process dies. This means stopping the service gracefully via systemctl will flush any uncommitted changes first.

`main()` — the core loop. `while true; do sleep $INTERVAL; commit and push if changes; done`

**Installed location:** `~/.local/bin/vault-observer.sh`

### `vault-observer.service`

The systemd user service config. Analogous to a PM2 config or Docker Compose service definition.

**Key directives:**

- `ExecStart` — points to the script location
- `Environment` — sets VAULT_DIR, INTERVAL_SECONDS, LOG_FILE, GIT_BRANCH, GIT_REMOTE
- `Restart=on-failure` — restarts if it crashes, not if stopped manually
- `CPUQuota=5%` — hard cap at 5% of one core
- `MemoryMax=64M` — hard cap at 64MB RAM
- `Nice=15` — low priority, yields to other processes
- `IOSchedulingClass=idle` — lowest IO priority

**Installed location:** `~/.config/systemd/user/vault-observer.service`

**Critical rule:** After editing this file, always run `systemctl --user daemon-reload` before restarting the service. If you only edit the `.sh` script, daemon-reload is not needed — just restart.

### `install.sh`

Interactive setup wizard. Run once. Analogous to `npm create vite@latest`.

**What it does:**

1. Checks for and installs `git` if missing
2. Prompts for vault path and interval
3. Copies `vault-observer.sh` to `~/.local/bin/`
4. Patches the service file with the user's actual vault path and interval
5. Copies service file to `~/.config/systemd/user/`
6. Runs `loginctl enable-linger` so the service survives user logout
7. Runs `systemctl --user daemon-reload && enable && start`
8. Confirms the service is active

---

## Problems Encountered During Setup — Full Chronology

### Problem 1: Push failed (exit 128) on first commit

**Log line:**

```bash
[ERROR] Push failed (exit 128) — commit is safe locally, will retry on next commit.
```

**Root cause:** The vault directory was initialized as a fresh git repo by the installer (because it had no `.git` folder), so it had no remote configured. The SSH test the user ran earlier was against a different directory.

**Diagnosis command:**

```bash
git -C ~/obsidian-vault remote -v
```

**Fix:**

```bash
git -C ~/obsidian-vault remote add origin git@github.com:MdSakifHossain/REPO.git
```

Then a manual push from VSCode worked because VSCode has its own credential layer.

### Problem 2: Terminal asked for username and password when pushing manually

**Root cause:** VSCode uses its own credential helper (libsecret/GNOME keyring integration) that silently authenticates. The system terminal had no credential helper configured.

**Fix:**

```bash
git config --global credential.helper store
git -C ~/obsidian-vault push origin main
```

Enter credentials once. After that, Git stores them in `~/.git-credentials` in plaintext. All subsequent pushes — from the terminal, from the observer script, from anywhere — work silently.

**Important:** GitHub no longer accepts account passwords for Git operations. The password field requires a Personal Access Token (PAT). Generate at: GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token → check `repo` scope → set `No expiration`.

### Problem 3: Continued "No staged changes" entries in log after push failure

**What happened:** After the push failed and credentials were fixed, the test file kept generating MODIFY events in the V1 log. Each event triggered the cooldown but since the file content hadn't changed (only metadata), git had nothing to commit.

**This was not a bug.** inotify fires on metadata changes too (e.g. access time). The `git diff --cached --quiet` check inside `commit_changes()` correctly detected nothing had actually changed and skipped the commit. The V2 polling model handles this even more cleanly — it just checks diff at wake time without reacting to every event.

---

## Key Conceptual Explanations Given During Session

### Why cooldown/debounce (V1) is wrong for this use case

The V1 model resets the timer on every file change. If you edit continuously, the timer never completes until you stop. In a 13-minute editing session followed by a power cut 10 seconds before the cooldown ends, you lose 13 minutes of work. The cooldown model is optimized for write efficiency (don't commit mid-session), not data safety.

### Why polling (V2) is correct for this use case

The interval is fixed and independent of user activity. It does not matter if you are actively editing or idle — the observer wakes up, checks, commits, and sleeps. The worst case is always exactly one interval. This is called a checkpoint interval pattern and is the standard approach in systems where data safety is the priority over write efficiency.

### What inotify is

The Linux kernel's built-in filesystem event notification system. Programs register interest in a directory and the kernel sends them events (MODIFY, CREATE, DELETE, etc.) the moment they happen. `inotifywait` is a command-line tool that wraps inotify. In V2 this entire system was removed — it is no longer needed.

### What systemd is

Linux's startup and process manager. Analogous to PM2 in the Node ecosystem. The `.service` file tells systemd what to run, when to start it, how to restart it on failure, and what resource limits to apply. `systemctl --user` commands manage services in the current user's scope (no sudo required).

### What `loginctl enable-linger` does

By default, user systemd services stop when the user logs out. `enable-linger` keeps them running even when no session is active. Required for the observer to survive a logout/login cycle.

### VSCode vs terminal credential difference

VSCode ships with a Git credential helper that integrates with the OS keychain (GNOME Keyring on Ubuntu). When you authenticate via VSCode, credentials are stored there. The terminal's Git installation uses a separate credential helper configuration. They are independent. Setting `credential.helper store` for the terminal makes it save credentials to `~/.git-credentials` after the first successful push, syncing the behavior.

### SSH "does not provide shell access" message

When running `ssh -T git@github.com`, GitHub responds with:

```bash
Hi MdSakifHossain! You've successfully authenticated, but GitHub does not provide shell access.
```

The second sentence is always there and always normal. GitHub is not a shell server. The important part is `You've successfully authenticated`. This means SSH keys are working correctly.

---

## Current State (End of Session)

- V2 polling observer is installed and running
- SSH authentication confirmed working
- GitHub remote confirmed configured on the vault
- Credentials stored via `credential.helper store`
- First successful push confirmed in log:

```bash
[24-04-2026 18:40:46] [INFO] Pushed successfully to origin/main
```

- Service set to start on boot via systemd user service with linger enabled

---

## Things the User May Want to Change Later

All of these are documented in the README. Summarized here for quick reference:

| Change                | File to edit                                               | Reload needed                     |
| --------------------- | ---------------------------------------------------------- | --------------------------------- |
| Interval length       | `~/.config/systemd/user/vault-observer.service`            | daemon-reload + restart           |
| Vault path            | `~/.config/systemd/user/vault-observer.service`            | daemon-reload + restart           |
| Commit message text   | `~/.local/bin/vault-observer.sh` (commit_changes function) | restart only                      |
| Which files to ignore | `~/obsidian-vault/.gitignore`                              | nothing, takes effect next commit |
| Script filename       | both service file and rename the script file               | daemon-reload + restart           |
| Git branch name       | service file, `GIT_BRANCH` variable                        | daemon-reload + restart           |
| Git remote name       | service file, `GIT_REMOTE` variable                        | daemon-reload + restart           |

---

## User's Mental Model (Important for Future Explanations)

The user thinks in JavaScript. Always use JS analogies first. Key mappings that worked well:

- systemd service → PM2 config / Docker Compose service
- `vault-observer.sh` → `server.js`
- `install.sh` → `npm create vite@latest`
- inotify → `fs.watch()` (Node)
- debounce/cooldown → `setTimeout` + `clearTimeout`
- polling loop → `while(true) { await sleep(); checkAndCommit(); }`
- `.gitignore` → already knows what this is from VSCode usage
- `git diff --cached` → checking if staging area has anything before committing

The user asks good, precise questions and catches real design flaws (like the 13-minute editing scenario). Do not oversimplify. Explain tradeoffs honestly.
