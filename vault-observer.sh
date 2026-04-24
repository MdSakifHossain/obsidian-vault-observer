#!/usr/bin/env zsh
# =============================================================================
# vault-observer.sh — Obsidian Git Auto-Commit Daemon
# Watches a vault directory and commits changes after a cooldown window.
# Compatible with: zsh, bash | Requires: inotifywait (inotify-tools), git
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — override via environment or edit here
# ---------------------------------------------------------------------------
VAULT_DIR="${VAULT_DIR:-$HOME/obsidian-vault}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-180}"      # 3 min default (180–300 recommended)
LOG_FILE="${LOG_FILE:-$HOME/.local/logs/vault-observer.log}"
MAX_LOG_LINES="${MAX_LOG_LINES:-500}"            # Rotate log after N lines
GIT_BRANCH="${GIT_BRANCH:-main}"
GIT_REMOTE="${GIT_REMOTE:-origin}"                  # remote name, almost always "origin"
COMMIT_AUTHOR_NAME="${COMMIT_AUTHOR_NAME:-Vault Observer}"
COMMIT_AUTHOR_EMAIL="${COMMIT_AUTHOR_EMAIL:-observer@local}"

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
PENDING=0
LAST_CHANGE_TS=0
PID_FILE="/tmp/vault-observer.pid"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts=$(date '+%d-%m-%Y %H:%M:%S')
    local line="[$ts] [$level] $msg"
    echo "$line"
    echo "$line" >> "$LOG_FILE"

    # Lightweight log rotation
    local line_count
    line_count=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    if (( line_count > MAX_LOG_LINES )); then
        local tmp
        tmp=$(mktemp)
        tail -n $(( MAX_LOG_LINES / 2 )) "$LOG_FILE" > "$tmp"
        mv "$tmp" "$LOG_FILE"
        log "INFO" "Log rotated — kept last $(( MAX_LOG_LINES / 2 )) lines."
    fi
}

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------
check_deps() {
    local missing=()
    for cmd in inotifywait git; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if (( ${#missing[@]} > 0 )); then
        log "ERROR" "Missing dependencies: ${missing[*]}"
        log "ERROR" "Install with: sudo apt install inotify-tools git"
        exit 1
    fi
}

check_vault() {
    if [[ ! -d "$VAULT_DIR" ]]; then
        log "ERROR" "Vault directory not found: $VAULT_DIR"
        exit 1
    fi
    if [[ ! -d "$VAULT_DIR/.git" ]]; then
        log "WARN" "No git repo found — initialising one in $VAULT_DIR"
        git -C "$VAULT_DIR" init -b "$GIT_BRANCH"
        git -C "$VAULT_DIR" add -A
        git -C "$VAULT_DIR" \
            -c "user.name=$COMMIT_AUTHOR_NAME" \
            -c "user.email=$COMMIT_AUTHOR_EMAIL" \
            commit -m "Observer: Initial commit — $(date '+%d-%m-%Y @%I:%M %p')" || true
        log "INFO" "Git repo initialised with initial commit."
    fi
}

# ---------------------------------------------------------------------------
# Commit logic
# ---------------------------------------------------------------------------
commit_changes() {
    local now
    now=$(date '+%d-%m-%Y @%I:%M %p')
    local msg="Observer: Pushed at $now"

    cd "$VAULT_DIR"

    # Stage everything (new, modified, deleted)
    git add -A

    # Only commit if there are staged changes
    if git diff --cached --quiet; then
        log "INFO" "No staged changes — skipping commit."
        PENDING=0
        return 0
    fi

    local changed_files
    changed_files=$(git diff --cached --name-only | wc -l)

    git -c "user.name=$COMMIT_AUTHOR_NAME" \
        -c "user.email=$COMMIT_AUTHOR_EMAIL" \
        commit -m "$msg" --quiet

    log "INFO" "Committed $changed_files file(s) — \"$msg\""
    PENDING=0

    # Push immediately after every successful commit
    push_changes
}

# ---------------------------------------------------------------------------
# Push logic
# ---------------------------------------------------------------------------
push_changes() {
    log "INFO" "Pushing to $GIT_REMOTE/$GIT_BRANCH ..."

    # Check if a remote even exists — if not, warn and skip (don't crash)
    if ! git -C "$VAULT_DIR" remote get-url "$GIT_REMOTE" &>/dev/null; then
        log "WARN" "No remote '$GIT_REMOTE' configured — skipping push."
        log "WARN" "To add one: git -C $VAULT_DIR remote add origin <your-github-url>"
        return 0
    fi

    # Timeout after 30s so a bad connection doesn't hang the loop forever
    if timeout 30 git -C "$VAULT_DIR" push "$GIT_REMOTE" "$GIT_BRANCH" --quiet; then
        log "INFO" "Pushed successfully to $GIT_REMOTE/$GIT_BRANCH"
    else
        local exit_code=$?
        if (( exit_code == 124 )); then
            log "ERROR" "Push timed out after 30s — will retry on next commit."
        else
            log "ERROR" "Push failed (exit $exit_code) — commit is safe locally, will retry on next commit."
        fi
        # Not fatal — the local commit already succeeded, your data is safe
    fi
}

# ---------------------------------------------------------------------------
# Graceful shutdown
# ---------------------------------------------------------------------------
cleanup() {
    log "INFO" "Observer shutting down (signal received)."
    if (( PENDING == 1 )); then
        log "WARN" "Pending changes detected on shutdown — committing now."
        commit_changes || log "ERROR" "Final commit failed."
    fi
    rm -f "$PID_FILE"
    exit 0
}
trap cleanup SIGTERM SIGINT SIGHUP

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"

    check_deps
    check_vault

    echo $$ > "$PID_FILE"
    log "INFO" "======================================================"
    log "INFO" "Vault Observer started (PID $$)"
    log "INFO" "Watching : $VAULT_DIR"
    log "INFO" "Cooldown : ${COOLDOWN_SECONDS}s"
    log "INFO" "Log      : $LOG_FILE"
    log "INFO" "======================================================"

    # inotifywait in monitor mode: streams events until killed
    # Exclude .git internals, swap files, and DS_Store noise
    inotifywait \
        --monitor \
        --recursive \
        --quiet \
        --format '%T %e %w%f' \
        --timefmt '%s' \
        --exclude '(\.git/|\.DS_Store|.*\.swp$|.*~$|\.obsidian/workspace\.json)' \
        --event modify,create,delete,moved_to,moved_from \
        "$VAULT_DIR" | \
    while IFS= read -r event_line; do
        local event_ts event_type event_path
        event_ts=$(echo "$event_line" | awk '{print $1}')
        event_type=$(echo "$event_line" | awk '{print $2}')
        event_path=$(echo "$event_line" | awk '{$1=$2=""; print substr($0,3)}')

        log "DEBUG" "Event: [$event_type] $event_path"

        PENDING=1
        LAST_CHANGE_TS=$event_ts

        # Cooldown: wait until no event has fired for COOLDOWN_SECONDS
        local now_ts elapsed
        while true; do
            sleep 10  # poll interval — low CPU cost
            now_ts=$(date +%s)
            elapsed=$(( now_ts - LAST_CHANGE_TS ))

            if (( elapsed >= COOLDOWN_SECONDS )); then
                log "INFO" "Cooldown elapsed (${elapsed}s) — triggering commit."
                commit_changes
                break
            fi
        done
    done
}

main "$@"
