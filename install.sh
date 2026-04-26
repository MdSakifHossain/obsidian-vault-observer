#!/usr/bin/env zsh
# =============================================================================
# install.sh — Vault Observer Installer
# Reads config.env from the same directory, installs everything, and starts
# the service. Re-run this any time you change config.env.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
CONFIG_FILE="$SCRIPT_DIR/config.env"
INSTALL_BIN="$HOME/.local/bin"
INSTALL_SYSTEMD="$HOME/.config/systemd/user"
LOG_DIR="$HOME/.local/logs"

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
print_step() { echo "\n\033[1;36m▸ $*\033[0m"; }
print_ok()   { echo "\033[0;32m  ✓ $*\033[0m"; }
print_warn() { echo "\033[0;33m  ⚠ $*\033[0m"; }
print_err()  { echo "\033[0;31m  ✗ $*\033[0m"; }

# ---------------------------------------------------------------------------
# Load config.env
# ---------------------------------------------------------------------------
print_step "Loading config.env..."

if [[ ! -f "$CONFIG_FILE" ]]; then
    print_err "config.env not found at $CONFIG_FILE"
    print_err "Make sure config.env is in the same folder as install.sh"
    exit 1
fi

# Source the config — this loads all variables into the current shell
source "$CONFIG_FILE"

# Expand $HOME manually in VAULT_DIR and LOG_FILE in case they used $HOME
VAULT_DIR="${VAULT_DIR/\$HOME/$HOME}"
LOG_FILE="${LOG_FILE/\$HOME/$HOME}"

print_ok "Config loaded."
echo "    VAULT_DIR        = $VAULT_DIR"
echo "    INTERVAL_SECONDS = $INTERVAL_SECONDS"
echo "    GIT_BRANCH       = $GIT_BRANCH"
echo "    GIT_REMOTE       = $GIT_REMOTE"
echo "    LOG_FILE         = $LOG_FILE"

# ---------------------------------------------------------------------------
# Confirm before proceeding
# ---------------------------------------------------------------------------
echo ""
echo -n "  Proceed with these settings? [Y/n]: "
read -r confirm
confirm="${confirm:-Y}"
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "  Aborted. Edit config.env and re-run install.sh."
    exit 0
fi

# ---------------------------------------------------------------------------
# Check dependencies
# ---------------------------------------------------------------------------
print_step "Checking dependencies..."

if ! command -v git &>/dev/null; then
    print_warn "git not found — installing..."
    sudo apt-get update -qq && sudo apt-get install -y git
    print_ok "git installed."
else
    print_ok "git already present."
fi

# ---------------------------------------------------------------------------
# Check vault directory
# ---------------------------------------------------------------------------
print_step "Checking vault directory..."

if [[ ! -d "$VAULT_DIR" ]]; then
    print_warn "$VAULT_DIR does not exist — creating it."
    mkdir -p "$VAULT_DIR"
fi
print_ok "Vault directory OK: $VAULT_DIR"

# ---------------------------------------------------------------------------
# Stop existing service if running
# ---------------------------------------------------------------------------
print_step "Stopping existing service if running..."

if systemctl --user is-active --quiet vault-observer.service 2>/dev/null; then
    systemctl --user stop vault-observer.service
    print_ok "Old service stopped."
else
    print_ok "No existing service running."
fi

# ---------------------------------------------------------------------------
# Install the observer script
# ---------------------------------------------------------------------------
print_step "Installing vault-observer.sh to $INSTALL_BIN ..."

mkdir -p "$INSTALL_BIN" "$LOG_DIR"
cp "$SCRIPT_DIR/vault-observer.sh" "$INSTALL_BIN/vault-observer.sh"
chmod +x "$INSTALL_BIN/vault-observer.sh"
print_ok "Script installed."

# ---------------------------------------------------------------------------
# Generate and install the service file from the template
# Replaces every __PLACEHOLDER__ with the actual value from config.env
# ---------------------------------------------------------------------------
print_step "Generating systemd service file..."

mkdir -p "$INSTALL_SYSTEMD"

sed \
    -e "s|__VAULT_DIR__|$VAULT_DIR|g" \
    -e "s|__INTERVAL_SECONDS__|$INTERVAL_SECONDS|g" \
    -e "s|__GIT_BRANCH__|$GIT_BRANCH|g" \
    -e "s|__GIT_REMOTE__|$GIT_REMOTE|g" \
    -e "s|__COMMIT_AUTHOR_NAME__|$COMMIT_AUTHOR_NAME|g" \
    -e "s|__COMMIT_AUTHOR_EMAIL__|$COMMIT_AUTHOR_EMAIL|g" \
    -e "s|__LOG_FILE__|$LOG_FILE|g" \
    -e "s|__MAX_LOG_LINES__|$MAX_LOG_LINES|g" \
    "$SCRIPT_DIR/vault-observer.service" \
    > "$INSTALL_SYSTEMD/vault-observer.service"

print_ok "Service file generated and installed."

# ---------------------------------------------------------------------------
# Enable linger so service survives logout
# ---------------------------------------------------------------------------
print_step "Enabling systemd linger..."

loginctl enable-linger "$USER" 2>/dev/null \
    && print_ok "Linger enabled." \
    || print_warn "Could not enable linger — service may stop on logout."

# ---------------------------------------------------------------------------
# Reload, enable, and start
# ---------------------------------------------------------------------------
print_step "Starting vault-observer..."

systemctl --user daemon-reload
systemctl --user enable vault-observer.service --quiet
systemctl --user start vault-observer.service
sleep 2

if systemctl --user is-active --quiet vault-observer.service; then
    print_ok "vault-observer is running!"
else
    print_err "Service failed to start."
    print_err "Check logs: journalctl --user -u vault-observer -f"
    exit 1
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "\033[1;32m  ✓ Installation complete.\033[0m"
echo ""
echo "  Useful commands:"
echo "    Watch live log : tail -f $LOG_FILE"
echo "    Service status : systemctl --user status vault-observer"
echo "    Stop           : systemctl --user stop vault-observer"
echo "    Restart        : systemctl --user restart vault-observer"
echo "    Journal log    : journalctl --user -u vault-observer -f"
echo ""
echo "  To change any setting:"
echo "    1. Edit config.env"
echo "    2. Run ./install.sh again"
echo ""
