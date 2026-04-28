#!/usr/bin/env bash
# =============================================================================
#  install.sh — Vault Observer Installer
#  Pure bash · No dependencies
# =============================================================================

set -euo pipefail

# ── Identity ──────────────────────────────────────────────────────────────────
SCRIPT_NAME="$(basename "$0")"
VERSION="3.0.0"

# ── Internal paths ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"
INSTALL_BIN="$HOME/.local/bin"
INSTALL_SYSTEMD="$HOME/.config/systemd/user"
LOG_DIR="$HOME/.local/logs"

# ── Colors ────────────────────────────────────────────────────────────────────
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
ORANGE='\033[38;5;209m'
BORANGE='\033[1;38;5;209m'
DIM_ORANGE='\033[2;38;5;209m'
BWHITE='\033[1;37m'
GREEN='\033[0;32m'
BGREEN='\033[1;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'

# ── Color helpers ─────────────────────────────────────────────────────────────
log_clr_l1() { echo -e "${ORANGE}${1}${RESET}"; }
log_clr_l2() { echo -e "${BORANGE}${1}${RESET}"; }
log_clr_l3() { echo -e "${DIM_ORANGE}${1}${RESET}"; }

# ── Text helpers ──────────────────────────────────────────────────────────────
log_txt_nm() { echo -e "${1}"; }
log_txt_bd() { echo -e "${BOLD}${1}${RESET}"; }
log_txt_dm() { echo -e "${DIM}${1}${RESET}"; }

# ── Semantic logging ──────────────────────────────────────────────────────────
log_info()  { echo -e "  ${ORANGE}ℹ${RESET}  $*"; }
log_ok()    { echo -e "  ${BGREEN}✔${RESET}  $*"; }
log_warn()  { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
log_fail()  { echo -e "\n  ${RED}✖  ERROR:${RESET}  $*\n" >&2; exit 1; }
log_label() { echo -e "  ${BORANGE}▸${RESET}  ${BWHITE}$*${RESET}"; }

# ── UI helpers ────────────────────────────────────────────────────────────────
divider()  { log_clr_l3 "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
thin_div() { log_txt_dm "  ──────────────────────────────────────────────────────────────────"; }

prompt_line() {
  echo -ne "  ${BORANGE}?${RESET}  ${BWHITE}${1}${RESET} ${DIM}(default: ${2})${RESET} ${ORANGE}›${RESET} "
}

step() {
  echo -e "  ${BORANGE}[${1}]${RESET}  ${BWHITE}${2}${RESET}"
}

# ── Banner ────────────────────────────────────────────────────────────────────
show_banner() {
  clear
  echo
  log_clr_l2 "  ██╗   ██╗ █████╗ ██╗   ██╗██╗  ████████╗"
  log_clr_l2 "  ██║   ██║██╔══██╗██║   ██║██║  ╚══██╔══╝"
  log_clr_l2 "  ██║   ██║███████║██║   ██║██║     ██║   "
  log_clr_l1 "  ╚██╗ ██╔╝██╔══██║██║   ██║██║     ██║   "
  log_clr_l1 "   ╚████╔╝ ██║  ██║╚██████╔╝███████╗██║   "
  log_clr_l3 "    ╚═══╝  ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝   "
  echo
  log_clr_l2 "    ██████╗ ██████╗ ███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗ "
  log_clr_l2 "   ██╔═══██╗██╔══██╗██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗"
  log_clr_l2 "   ██║   ██║██████╔╝███████╗█████╗  ██████╔╝██║   ██║█████╗  ██████╔╝"
  log_clr_l1 "   ██║   ██║██╔══██╗╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██╔══██╗"
  log_clr_l1 "   ╚██████╔╝██████╔╝███████║███████╗██║  ██║ ╚████╔╝ ███████╗██║  ██║"
  log_clr_l3 "    ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝"
  echo
  log_txt_dm "  v${VERSION} · Pure Bash · No dependencies"
  echo
  divider
  echo
}

# ── Help ──────────────────────────────────────────────────────────────────────
show_help() {
  echo
  echo -e "  ${BORANGE}${SCRIPT_NAME}${RESET} ${DIM}v${VERSION}${RESET}"
  echo
  echo -e "  ${BWHITE}Installs and starts the Vault Observer systemd service.${RESET}"
  echo -e "  ${BWHITE}Reads all settings from ${RESET}${ORANGE}config.env${RESET}${BWHITE} in the same directory.${RESET}"
  echo -e "  ${BWHITE}Re-run any time you change ${RESET}${ORANGE}config.env${RESET}${BWHITE} to apply updates.${RESET}"
  echo
  echo -e "  ${BORANGE}Usage${RESET}"
  thin_div
  echo -e "    ${BWHITE}./${SCRIPT_NAME} ${DIM}[options]${RESET}"
  echo
  echo -e "  ${BORANGE}Options${RESET}"
  thin_div
  echo -e "    ${BWHITE}-y, --yes${RESET}       Skip the confirmation prompt."
  echo -e "    ${BWHITE}-h, --help${RESET}      Show this help message."
  echo -e "    ${BWHITE}-v, --version${RESET}   Show version number."
  echo
  echo -e "  ${BORANGE}Workflow${RESET}"
  thin_div
  echo -e "    ${DIM}1.${RESET}  Edit   ${ORANGE}config.env${RESET}"
  echo -e "    ${DIM}2.${RESET}  Run    ${BWHITE}./${SCRIPT_NAME}${RESET}"
  echo -e "    ${DIM}3.${RESET}  Done"
  echo
  echo -e "  ${BORANGE}Examples${RESET}"
  thin_div
  echo -e "    ${DIM}\$${RESET} ./${SCRIPT_NAME}"
  echo -e "    ${DIM}\$${RESET} ./${SCRIPT_NAME} --yes"
  echo
  divider
  echo
}

# ── Flag parsing ──────────────────────────────────────────────────────────────
SKIP_CONFIRM=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)      SKIP_CONFIRM=true;  shift ;;
    -h|--help)     show_help;          exit 0 ;;
    -v|--version)  echo "${SCRIPT_NAME} v${VERSION}"; exit 0 ;;
    -*)            log_fail "Unknown flag: $1. Run with --help for usage." ;;
    *)             shift ;;
  esac
done

# ── Banner ────────────────────────────────────────────────────────────────────
show_banner

# ── Step 1 — Load config.env ──────────────────────────────────────────────────
step "1" "Loading Configuration"
thin_div
echo
log_info "Reading ${BOLD}config.env${RESET}..."
echo

[[ ! -f "$CONFIG_FILE" ]] && log_fail "config.env not found at ${CONFIG_FILE}\n     Make sure config.env is in the same folder as ${SCRIPT_NAME}."

source "$CONFIG_FILE"

# Expand $HOME in paths in case the user wrote $HOME literally in config.env
VAULT_DIR="${VAULT_DIR/\$HOME/$HOME}"
LOG_FILE="${LOG_FILE/\$HOME/$HOME}"

log_ok "Config loaded successfully."
echo
echo -e "  ${DIM}  VAULT_DIR        ${RESET}  ${BWHITE}${VAULT_DIR}${RESET}"
echo -e "  ${DIM}  INTERVAL_SECONDS ${RESET}  ${BWHITE}${INTERVAL_SECONDS}s${RESET}"
echo -e "  ${DIM}  GIT_BRANCH       ${RESET}  ${BWHITE}${GIT_BRANCH}${RESET}"
echo -e "  ${DIM}  GIT_REMOTE       ${RESET}  ${BWHITE}${GIT_REMOTE}${RESET}"
echo -e "  ${DIM}  LOG_FILE         ${RESET}  ${BWHITE}${LOG_FILE}${RESET}"
echo

# ── Confirmation ──────────────────────────────────────────────────────────────
if [[ "$SKIP_CONFIRM" == false ]]; then
  thin_div
  echo -ne "  ${BORANGE}?${RESET}  ${BWHITE}Proceed with these settings?${RESET} ${DIM}(Enter = yes, Ctrl+C = abort)${RESET} ${ORANGE}›${RESET} "
  read -r CONFIRM
  CONFIRM="${CONFIRM,,}"
  if [[ "$CONFIRM" == "n" || "$CONFIRM" == "no" ]]; then
    echo
    log_warn "Aborted. Edit config.env and re-run ./${SCRIPT_NAME}."
    echo
    divider
    echo
    exit 0
  fi
fi
echo

# ── Step 2 — Dependencies ─────────────────────────────────────────────────────
step "2" "Checking Dependencies"
thin_div
echo

if ! command -v git &>/dev/null; then
  log_warn "git not found — installing now..."
  sudo apt-get update -qq && sudo apt-get install -y git \
    || log_fail "Could not install git. Run manually: sudo apt install git"
  log_ok "git installed."
else
  log_ok "git is present."
fi
echo

# ── Step 3 — Vault directory ──────────────────────────────────────────────────
step "3" "Checking Vault Directory"
thin_div
echo

if [[ ! -d "$VAULT_DIR" ]]; then
  log_warn "${VAULT_DIR} does not exist — creating it."
  mkdir -p "$VAULT_DIR"
fi
log_ok "Vault directory confirmed: ${BOLD}${VAULT_DIR}${RESET}"
echo

# ── Step 4 — Stop existing service ───────────────────────────────────────────
step "4" "Stopping Existing Service"
thin_div
echo

if systemctl --user is-active --quiet vault-observer.service 2>/dev/null; then
  systemctl --user stop vault-observer.service
  log_ok "Running service stopped."
else
  log_ok "No existing service was running."
fi
echo

# ── Step 5 — Install observer script ─────────────────────────────────────────
step "5" "Installing Observer Script"
thin_div
echo

mkdir -p "$INSTALL_BIN" "$LOG_DIR"
cp "$SCRIPT_DIR/vault-observer.sh" "$INSTALL_BIN/vault-observer.sh"
chmod +x "$INSTALL_BIN/vault-observer.sh"
log_ok "Script installed to ${BOLD}${INSTALL_BIN}/vault-observer.sh${RESET}"
echo

# ── Step 6 — Generate service file ───────────────────────────────────────────
step "6" "Generating systemd Service File"
thin_div
echo

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

log_ok "Service file written to ${BOLD}${INSTALL_SYSTEMD}/vault-observer.service${RESET}"
echo

# ── Step 7 — Enable linger ────────────────────────────────────────────────────
step "7" "Enabling systemd Linger"
thin_div
echo

if loginctl enable-linger "$USER" 2>/dev/null; then
  log_ok "Linger enabled — service will survive logout."
else
  log_warn "Could not enable linger — service may stop on logout."
fi
echo

# ── Step 8 — Start service ────────────────────────────────────────────────────
step "8" "Starting Vault Observer"
thin_div
echo

systemctl --user daemon-reload
systemctl --user enable vault-observer.service --quiet
systemctl --user start vault-observer.service
sleep 2

if systemctl --user is-active --quiet vault-observer.service; then
  log_ok "vault-observer is ${BGREEN}active and running${RESET}."
else
  log_fail "Service failed to start.\n     Check: journalctl --user -u vault-observer -f"
fi
echo

# ── Done ──────────────────────────────────────────────────────────────────────
divider
echo
echo -e "${BORANGE}  ╔══════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BORANGE}  ║${RESET}${BOLD}               ✅  Observer is watching.                          ${BORANGE}║${RESET}"
echo -e "${BORANGE}  ╚══════════════════════════════════════════════════════════════════╝${RESET}"
echo
log_label "Vault      :  ${VAULT_DIR}"
log_label "Interval   :  every ${INTERVAL_SECONDS}s"
log_label "Max loss   :  ${INTERVAL_SECONDS}s of work"
log_label "Log file   :  ${LOG_FILE}"
echo
thin_div
echo
log_info "Watch live     ${DIM}→${RESET}  tail -f ${LOG_FILE}"
log_info "Service status ${DIM}→${RESET}  systemctl --user status vault-observer"
log_info "Stop           ${DIM}→${RESET}  systemctl --user stop vault-observer"
log_info "Restart        ${DIM}→${RESET}  systemctl --user restart vault-observer"
echo
thin_div
echo
log_info "To apply future config changes:"
echo -e "     ${DIM}1.${RESET}  Edit   ${ORANGE}config.env${RESET}"
echo -e "     ${DIM}2.${RESET}  Run    ${BWHITE}./${SCRIPT_NAME}${RESET}"
echo
divider
echo
