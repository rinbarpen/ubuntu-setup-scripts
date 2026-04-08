#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

# --- nvm / Node.js ---
log_info "Installing nvm..."
export NVM_DIR="$HOME/.nvm"
if [[ ! -d "$NVM_DIR" ]]; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi
# nvm.sh uses unbound variables internally; temporarily relax set -u
# shellcheck source=/dev/null
set +u; source "$NVM_DIR/nvm.sh"; set -u
nvm install --lts
nvm use --lts
log_info "Node $(node -v) installed"

# --- Python ---
log_info "Installing Python3..."
sudo apt-get install -y python3 python3-pip python3-venv

# --- Rust ---
log_info "Installing Rust..."
if ! command -v rustup &>/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  # shellcheck source=/dev/null
  source "$HOME/.cargo/env"
fi

# --- miniconda ---
log_info "Installing miniconda..."
CONDA_DIR="$HOME/miniconda3"
if [[ ! -d "$CONDA_DIR" ]]; then
  CONDA_INSTALLER="/tmp/miniconda.sh"
  curl -fsSL "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh" \
    -o "$CONDA_INSTALLER"
  bash "$CONDA_INSTALLER" -b -p "$CONDA_DIR"
  rm "$CONDA_INSTALLER"
  "$CONDA_DIR/bin/conda" init bash
fi

# --- uv ---
log_info "Installing uv..."
if ! command -v uv &>/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
else
  log_info "uv already installed, skipping"
fi

# --- Go ---
log_info "Installing Go..."
GO_LATEST=$(curl -fsSL "https://go.dev/VERSION?m=text" | head -1)
GO_CURRENT=$(/usr/local/go/bin/go version 2>/dev/null | awk '{print $3}' || echo "none")
if [[ "$GO_CURRENT" == "$GO_LATEST" ]]; then
  log_info "Go $GO_LATEST already installed, skipping"
else
  GO_TARBALL="${GO_LATEST}.linux-amd64.tar.gz"
  curl -fsSL "https://go.dev/dl/${GO_TARBALL}" -o "/tmp/${GO_TARBALL}"
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf "/tmp/${GO_TARBALL}"
  rm "/tmp/${GO_TARBALL}"
  log_info "Go ${GO_LATEST} installed"
fi
GO_VERSION="$GO_LATEST"

# Add Go to PATH in bashrc
if ! grep -q '/usr/local/go/bin' "$HOME/.bashrc"; then
  echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> "$HOME/.bashrc"
fi
# Add to fish
mkdir -p "$HOME/.config/fish/conf.d"
cat > "$HOME/.config/fish/conf.d/go.fish" << 'EOF'
set -gx PATH $PATH /usr/local/go/bin $HOME/go/bin
EOF

log_info "Go $GO_VERSION installed"
log_info "languages: done (restart shell or source ~/.bashrc)"
