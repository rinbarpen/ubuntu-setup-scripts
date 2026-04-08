#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

log_info "Updating package lists..."
sudo apt-get update -qq

log_info "Installing base packages..."
sudo apt-get install -y \
  build-essential curl wget git vim neovim tmux htop btop aria2 \
  fzf ripgrep bat eza \
  zip unzip p7zip-full p7zip-rar tar gzip bzip2 xz-utils zstd \
  net-tools iproute2 iputils-ping nmap traceroute dnsutils

# nvtop
if sudo apt-get install -y nvtop 2>/dev/null; then
  log_info "nvtop installed via apt"
else
  log_warn "nvtop not in apt, trying pip..."
  pip3 install nvtop 2>/dev/null || log_warn "nvtop install failed, skipping"
fi

# Docker
log_info "Installing Docker..."
sudo apt-get install -y ca-certificates gnupg lsb-release
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -qq
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker "$USER"
log_info "Docker installed. Re-login required for group membership."

# xrdp
log_info "Installing xrdp..."
sudo apt-get install -y xrdp
sudo systemctl enable --now xrdp
sudo adduser xrdp ssl-cert 2>/dev/null || true
if sudo ufw status 2>/dev/null | grep -q "Status: active"; then
  sudo ufw allow 3389/tcp
  log_info "Firewall rule added for RDP (3389/tcp)"
fi

log_info "ubuntu-base: done"
