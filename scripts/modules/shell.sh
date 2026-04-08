#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

log_info "Installing fish shell..."
sudo apt-get install -y fish

if confirm "Set fish as default shell?"; then
  chsh -s "$(which fish)"
fi

# Proxy address
read -r -p "Proxy address for proxy_on (default: http://127.0.0.1:7890): " PROXY_ADDR
PROXY_ADDR="${PROXY_ADDR:-http://127.0.0.1:7890}"

FISH_FUNC_DIR="$HOME/.config/fish/functions"
mkdir -p "$FISH_FUNC_DIR"

# proxy_on.fish
cat > "${FISH_FUNC_DIR}/proxy_on.fish" << EOF
function proxy_on
    set -gx http_proxy ${PROXY_ADDR}
    set -gx https_proxy ${PROXY_ADDR}
    set -gx all_proxy ${PROXY_ADDR}
    echo "Proxy ON: ${PROXY_ADDR}"
end
EOF

# proxy_off.fish
cat > "${FISH_FUNC_DIR}/proxy_off.fish" << 'EOF'
function proxy_off
    set -e http_proxy
    set -e https_proxy
    set -e all_proxy
    echo "Proxy OFF"
end
EOF

# proxy_status.fish
cat > "${FISH_FUNC_DIR}/proxy_status.fish" << 'EOF'
function proxy_status
    echo "http_proxy:  $http_proxy"
    echo "https_proxy: $https_proxy"
    echo "all_proxy:   $all_proxy"
end
EOF

# Bash equivalents
cat >> "$HOME/.bashrc" << EOF

# Proxy helpers (added by setup)
PROXY_ADDR="${PROXY_ADDR}"
proxy_on()     { export http_proxy=\$PROXY_ADDR https_proxy=\$PROXY_ADDR all_proxy=\$PROXY_ADDR; echo "Proxy ON: \$PROXY_ADDR"; }
proxy_off()    { unset http_proxy https_proxy all_proxy; echo "Proxy OFF"; }
proxy_status() { echo "http_proxy: \$http_proxy"; echo "https_proxy: \$https_proxy"; echo "all_proxy: \$all_proxy"; }
EOF

log_info "shell: done"
