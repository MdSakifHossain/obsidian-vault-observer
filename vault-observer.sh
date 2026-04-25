#!/usr/bin/env zsh
# =============================================================================
# vault-observer.sh — Obsidian Git Auto-Commit Daemon (Polling Model)
# Wakes up every INTERVAL_SECONDS, checks for changes, commits and pushes.
# Maximum possible data loss = INTERVAL_SECONDS. Always. No exceptions.
# Compatible with: zsh, bash | Requires: git
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — edit these to match your setup
# ---------------------------------------------------------------------------
VAULT_DIR="${VAULT_DIR:-$HOME/obsidian-vault}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-180}"     # how often to wake up and check
LOG_FILE="${LOG_FILE:-$HOME/.local/logs/vault-observer.log}"
MAX_LOG_LINES="${MAX_LOG_LINES:-500}"
GIT_BRANCH="${GIT_BRANCH:-main}"
GIT_REMOTE="${GIT_REMOTE:-origin}"
COMMIT_AUTHOR_NAME="${COMMIT_AUTHOR_NAME:-Vault Observer}"
COMMIT_AUTHOR_EMAIL="${COMMIT_AUTHOR_EMAIL:-observer@local}"

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

    # Lightweight log rotation — keeps file from growing forever
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
    if ! command -v git &>/dev/null; then
        log "ERROR" "git is not installed. Run: sudo apt install git"
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
            commit -m "Observer: Initial commit — $(date '+%d-%m-%Y %I:%M %p')" || true
        log "INFO" "Git repo initialised."
    fi
}

# ---------------------------------------------------------------------------
# Commit — stages and commits everything, returns 0 if committed, 1 if nothing to commit
# ---------------------------------------------------------------------------
commit_changes() {
    local now
    now=$(date '+%d-%m-%Y %I:%M %p')
    local msg="Observer: Pushed at $now"

    cd "$VAULT_DIR"
    git add -A

    # Nothing staged? bail out early
    if git diff --cached --quiet; then
        return 1
    fi

    local changed_files
    changed_files=$(git diff --cached --name-only | wc -l)

    git -c "user.name=$COMMIT_AUTHOR_NAME" \
        -c "user.email=$COMMIT_AUTHOR_EMAIL" \
        commit -m "$msg" --quiet

    log "INFO" "Committed $changed_files file(s) — \"$msg\""
    return 0
}

# ---------------------------------------------------------------------------
# Push — runs after every successful commit
# ---------------------------------------------------------------------------
push_changes() {
    # No remote configured? warn and skip — don't crash
    if ! git -C "$VAULT_DIR" remote get-url "$GIT_REMOTE" &>/dev/null; then
        log "WARN" "No remote '$GIT_REMOTE' found — skipping push."
        log "WARN" "To add one: git -C $VAULT_DIR remote add origin <your-github-url>"
        return 0
    fi

    if timeout 30 git -C "$VAULT_DIR" push "$GIT_REMOTE" "$GIT_BRANCH" --quiet; then
        log "INFO" "Pushed successfully to $GIT_REMOTE/$GIT_BRANCH"
    else
        local exit_code=$?
        if (( exit_code == 124 )); then
            log "ERROR" "Push timed out after 30s — commit is safe locally, will retry next cycle."
        else
            log "ERROR" "Push failed (exit $exit_code) — commit is safe locally, will retry next cycle."
        fi
    fi
}

# ---------------------------------------------------------------------------
# Graceful shutdown — commit any pending changes before dying
# ---------------------------------------------------------------------------
cleanup() {
    log "INFO" "Observer shutting down (signal received)."
    log "INFO" "Running final checkpoint before exit..."
    if commit_changes; then
        push_changes
    else
        log "INFO" "Nothing to commit on shutdown."
    fi
    rm -f "/tmp/vault-observer.pid"
    exit 0
}
trap cleanup SIGTERM SIGINT SIGHUP

# ---------------------------------------------------------------------------
# Main loop — the polling model
# ---------------------------------------------------------------------------
main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"

    check_deps
    check_vault

    echo $$ > "/tmp/vault-observer.pid"

    log "INFO" "======================================================"
    log "INFO" "Vault Observer started (PID $$)"
    log "INFO" "Watching  : $VAULT_DIR"
    log "INFO" "Interval  : every ${INTERVAL_SECONDS}s"
    log "INFO" "Max loss  : ${INTERVAL_SECONDS}s of work"
    log "INFO" "Log       : $LOG_FILE"
    log "INFO" "======================================================"

    # The core loop — dead simple
    while true; do

        # Sleep first — no point checking the moment we boot
        sleep "$INTERVAL_SECONDS"

        log "INFO" "Checkpoint — scanning for changes..."

        # commit_changes returns 0 if it committed, 1 if nothing changed
        if commit_changes; then
            push_changes
        else
            log "INFO" "No changes detected — going back to sleep."
        fi

    done
}

main "$@"
