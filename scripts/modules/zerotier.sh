#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

log_info "Installing ZeroTier..."
curl -s https://install.zerotier.com | sudo bash
sudo systemctl enable --now zerotier-one
log_info "ZeroTier service started"

if confirm "Join a ZeroTier network?"; then
  read -r -p "Network ID: " ZT_NET_ID
  if [[ -n "$ZT_NET_ID" ]]; then
    sudo zerotier-cli join "$ZT_NET_ID"
    log_info "Joined network $ZT_NET_ID (pending authorization)"
  fi
fi

log_info "zerotier: done"
