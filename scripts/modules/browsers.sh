#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

BROWSER_CHOICES=$(whiptail --title "Browsers" --checklist \
  "Select browsers to install:" 12 50 2 \
  "chrome"   "Google Chrome"  ON \
  "firefox"  "Firefox"        ON \
  3>&1 1>&2 2>&3) || { log_warn "Skipped browser selection"; exit 0; }

SELECTED=$(echo "$BROWSER_CHOICES" | tr -d '"')

if echo "$SELECTED" | grep -Fqw "chrome"; then
  if command -v google-chrome &>/dev/null; then
    log_info "Google Chrome already installed, skipping"
  else
    log_info "Installing Google Chrome..."
    curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
      -o /tmp/chrome.deb
    sudo apt-get install -y /tmp/chrome.deb || sudo apt-get install -yf
    rm /tmp/chrome.deb
  fi
fi

if echo "$SELECTED" | grep -Fqw "firefox"; then
  log_info "Installing Firefox..."
  sudo apt-get install -y firefox || \
    (log_warn "apt firefox failed, trying snap..." && sudo snap install firefox)
fi

log_info "browsers: done"
