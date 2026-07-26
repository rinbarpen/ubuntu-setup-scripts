#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info() { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_err()  { echo -e "${RED}[ERR]${NC}   $*" >&2; }

sudo_check() {
  sudo -v
  while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &
}

sudo_check

# ---- 1. fish shell ----
log_info "Installing fish shell..."
sudo apt-get install -y fish
sudo chsh -s "$(which fish)" "$USER" || log_warn "chsh failed — fish may not be in /etc/shells"
log_info "fish $(fish --version) installed, default shell set"

# ---- 2. nvm + Node LTS ----
log_info "Installing nvm..."
export NVM_DIR="$HOME/.nvm"
if [[ ! -d "$NVM_DIR" ]]; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
fi
set +u; source "$NVM_DIR/nvm.sh"; set -u
nvm install --lts
nvm alias default 'lts/*'
log_info "Node $(node -v), npm $(npm -v) installed"

# ---- 3. bun ----
log_info "Installing bun..."
npm install -g bun
log_info "bun $(bun --version) installed"

echo ""
log_info "===== Prepare complete ====="
echo "  fish: $(fish --version)"
echo "  node: $(node --version)"
echo "  npm:  $(npm --version)"
echo "  bun:  $(bun --version)"
