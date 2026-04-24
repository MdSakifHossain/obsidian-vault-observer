#!/usr/bin/env zsh
# =============================================================================
# install.sh — One-shot installer for vault-observer
# Run from the cloned/extracted directory: ./install.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
INSTALL_BIN="$HOME/.local/bin"
INSTALL_SYSTEMD="$HOME/.config/systemd/user"
LOG_DIR="$HOME/.local/logs"

print_step() { echo "\n\033[1;36m▸ $*\033[0m"; }
print_ok()   { echo "\033[0;32m  ✓ $*\033[0m"; }
print_warn() { echo "\033[0;33m  ⚠ $*\033[0m"; }
print_err()  { echo "\033[0;31m  ✗ $*\033[0m"; }

# ── Check inotify-tools ───────────────────────────────────────────────────
print_step "Checking dependencies..."
if ! command -v inotifywait &>/dev/null; then
    print_warn "inotify-tools not found. Installing..."
    sudo apt-get update -qq && sudo apt-get install -y inotify-tools
    print_ok "inotify-tools installed."
else
    print_ok "inotify-tools already present."
fi

if ! command -v git &>/dev/null; then
    print_warn "git not found. Installing..."
    sudo apt-get install -y git
    print_ok "git installed."
else
    print_ok "git already present."
fi

# ── Ask for vault path ────────────────────────────────────────────────────
print_step "Vault configuration"
echo -n "  Enter full path to your Obsidian vault [$HOME/obsidian-vault]: "
read -r vault_path
vault_path="${vault_path:-$HOME/obsidian-vault}"

if [[ ! -d "$vault_path" ]]; then
    print_warn "Directory $vault_path does not exist yet — it will be created."
    mkdir -p "$vault_path"
fi

echo -n "  Cooldown in seconds (120–300 recommended) [180]: "
read -r cooldown
cooldown="${cooldown:-180}"

# ── Install script ────────────────────────────────────────────────────────
print_step "Installing vault-observer.sh to $INSTALL_BIN ..."
mkdir -p "$INSTALL_BIN" "$LOG_DIR"
cp "$SCRIPT_DIR/vault-observer.sh" "$INSTALL_BIN/vault-observer.sh"
chmod +x "$INSTALL_BIN/vault-observer.sh"
print_ok "Script installed."

# ── Install systemd unit ──────────────────────────────────────────────────
print_step "Installing systemd user service..."
mkdir -p "$INSTALL_SYSTEMD"

# Patch the service file with the user's vault path and cooldown
sed \
    -e "s|Environment=VAULT_DIR=%h/obsidian-vault|Environment=VAULT_DIR=$vault_path|" \
    -e "s|Environment=COOLDOWN_SECONDS=180|Environment=COOLDOWN_SECONDS=$cooldown|" \
    -e "s|ReadWritePaths=%h/obsidian-vault %h/.local|ReadWritePaths=$vault_path %h/.local|" \
    "$SCRIPT_DIR/vault-observer.service" \
    > "$INSTALL_SYSTEMD/vault-observer.service"

print_ok "Service unit installed."

# ── Enable linger so service survives logout ──────────────────────────────
print_step "Enabling systemd linger (keeps service alive after logout)..."
loginctl enable-linger "$USER" 2>/dev/null && print_ok "Linger enabled." \
    || print_warn "Could not enable linger — service will stop on logout."

# ── Enable and start ─────────────────────────────────────────────────────
print_step "Enabling and starting vault-observer..."
systemctl --user daemon-reload
systemctl --user enable vault-observer.service
systemctl --user start vault-observer.service
sleep 2

if systemctl --user is-active --quiet vault-observer.service; then
    print_ok "vault-observer is running!"
else
    print_err "Service failed to start. Check: journalctl --user -u vault-observer.service"
    exit 1
fi

# ── Done ──────────────────────────────────────────────────────────────────
echo ""
echo "\033[1;32m  Installation complete.\033[0m"
echo ""
echo "  Useful commands:"
echo "    Status  : systemctl --user status vault-observer"
echo "    Logs    : journalctl --user -u vault-observer -f"
echo "    Script log: tail -f $LOG_DIR/vault-observer.log"
echo "    Stop    : systemctl --user stop vault-observer"
echo "    Restart : systemctl --user restart vault-observer"
echo ""
