#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

# git-lfs
log_info "Installing git-lfs..."
sudo apt-get install -y git-lfs
git lfs install

# user.name / email
read -r -p "Git user.name (leave blank to skip): " GIT_NAME
[[ -n "$GIT_NAME" ]] && git config --global user.name "$GIT_NAME"

read -r -p "Git user.email (leave blank to skip): " GIT_EMAIL
[[ -n "$GIT_EMAIL" ]] && git config --global user.email "$GIT_EMAIL"

# SSH key
SSH_KEY="$HOME/.ssh/id_ed25519"
if [[ ! -f "$SSH_KEY" ]]; then
  log_info "Generating SSH key..."
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t ed25519 -C "${GIT_EMAIL:-$(hostname)}" -f "$SSH_KEY" -N ""
fi
log_info "Your SSH public key:"
cat "${SSH_KEY}.pub"

# Aliases
git config --global alias.st status
git config --global alias.co checkout
git config --global alias.br branch
git config --global alias.lg "log --oneline --graph --decorate --all"

# Proxy
if confirm "Configure git HTTP proxy?"; then
  read -r -p "Proxy address (e.g. http://127.0.0.1:7890): " PROXY_ADDR
  if [[ -n "$PROXY_ADDR" ]]; then
    git config --global http.proxy "$PROXY_ADDR"
    git config --global https.proxy "$PROXY_ADDR"
  fi
fi

log_info "git: done"
