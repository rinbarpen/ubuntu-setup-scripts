#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

need_cmd npm
need_cmd python3

PASEO_CONFIG="${HOME}/.paseo/config.json"

# Install paseo CLI (skip if already installed)
if command -v paseo &>/dev/null; then
  log_info "paseo already installed ($(command -v paseo)), skipping npm install"
else
  log_info "Installing paseo CLI..."
  npm install -g @getpaseo/cli --ignore-scripts
fi

mkdir -p "$(dirname "$PASEO_CONFIG")"

# Daemon listen address selection
PASEO_LISTEN="127.0.0.1:6767"
if [[ -f "$PASEO_CONFIG" ]]; then
  _existing_listen=$(python3 -c "import json; print(json.load(open('$PASEO_CONFIG')).get('daemon',{}).get('listen',''))" 2>/dev/null || echo "")
  [[ -n "$_existing_listen" ]] && PASEO_LISTEN="$_existing_listen"
fi

if command -v whiptail &>/dev/null; then
  _listen_info="当前: ${PASEO_LISTEN}"
  LISTEN_CHOICE=$(whiptail --title "Paseo Daemon Listen" --menu "Select daemon listen address:\n${_listen_info}" 18 70 4 \
      "127.0.0.1:6767" "本地 (localhost only — 推荐)" \
      "0.0.0.0:6767"   "所有网卡 (all interfaces)" \
      "custom"          "自定义 (custom address)" \
      3>&1 1>&2 2>&3) || LISTEN_CHOICE=""

  case "$LISTEN_CHOICE" in
    127.0.0.1:6767|0.0.0.0:6767) PASEO_LISTEN="$LISTEN_CHOICE" ;;
    custom) read -r -p "Enter listen address (e.g. 0.0.0.0:6767): " PASEO_LISTEN ;;
    *) ;;  # keep existing default
  esac
fi
export PASEO_LISTEN

# MCP toggle
MCP_ENABLED="true"
if [[ -f "$PASEO_CONFIG" ]]; then
  _existing_mcp=$(python3 -c "import json; print(json.load(open('$PASEO_CONFIG')).get('daemon',{}).get('mcp',{}).get('enabled',''))" 2>/dev/null || echo "")
  [[ "$_existing_mcp" == "False" ]] && MCP_ENABLED="false"
fi

if command -v whiptail &>/dev/null; then
  _mcp_label="当前: $([[ "$MCP_ENABLED" == "true" ]] && echo "启用" || echo "禁用")"
  if whiptail --title "Paseo MCP" --yesno "Enable daemon MCP server?\n${_mcp_label}" 10 50; then
    MCP_ENABLED="true"
  else
    MCP_ENABLED="false"
  fi
fi
export MCP_ENABLED

# Optional password auth
PASEO_PASSWORD_HASH=""
if [[ -f "$PASEO_CONFIG" ]]; then
  _existing_hash=$(python3 -c "import json; print(json.load(open('$PASEO_CONFIG')).get('daemon',{}).get('auth',{}).get('password',''))" 2>/dev/null || echo "")
  [[ -n "$_existing_hash" ]] && PASEO_PASSWORD_HASH="$_existing_hash"
fi

SET_PASSWORD="no"
if [[ -n "$PASEO_PASSWORD_HASH" ]]; then
  log_info "Daemon password is already set"
  confirm "Change daemon password?" && SET_PASSWORD="yes"
else
  confirm "Set a password for the paseo daemon?" && SET_PASSWORD="yes"
fi

if [[ "$SET_PASSWORD" == "yes" ]]; then
  if command -v whiptail &>/dev/null; then
    PASEO_PW=$(whiptail --title "Paseo Password" --passwordbox "Enter daemon password:" 10 50 3>&1 1>&2 2>&3) || PASEO_PW=""
  else
    read -r -s -p "Enter daemon password: " PASEO_PW; echo ""
  fi
  if [[ -n "$PASEO_PW" ]]; then
    PASEO_PASSWORD_HASH=$(python3 -c "import bcrypt; print(bcrypt.hashpw('$PASEO_PW'.encode(), bcrypt.gensalt()).decode())" 2>/dev/null || echo "")
    if [[ -z "$PASEO_PASSWORD_HASH" ]]; then
      log_warn "bcrypt not available — storing plaintext (paseo will hash on startup)"
      PASEO_PASSWORD_HASH="__PLAINTEXT__${PASEO_PW}"
    fi
    unset PASEO_PW
  else
    log_warn "Empty password — skipping"
  fi
fi
export PASEO_PASSWORD_HASH

# Build hostnames array based on listen address
HOSTNAMES='["localhost", ".localhost"]'
if [[ "$PASEO_LISTEN" == 0.0.0.0:* ]]; then
  _hostname=$(hostname 2>/dev/null || echo "")
  if [[ -n "$_hostname" ]]; then
    HOSTNAMES="[\"localhost\", \".localhost\", \"${_hostname}\", \".${_hostname}\"]"
  else
    HOSTNAMES="[\"localhost\", \".localhost\"]"
  fi
fi
export HOSTNAMES

# Write config.json
python3 - "$PASEO_CONFIG" << 'PYEOF'
import json
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])

try:
    config = json.loads(path.read_text())
except Exception:
    config = {}

config["$schema"] = "https://paseo.sh/schemas/paseo.config.v1.json"
config["version"] = 1

daemon = config.setdefault("daemon", {})
daemon["listen"] = os.environ.get("PASEO_LISTEN", "127.0.0.1:6767")

hostnames_raw = os.environ.get("HOSTNAMES", '["localhost", ".localhost"]')
daemon["hostnames"] = json.loads(hostnames_raw)

mcp_enabled = os.environ.get("MCP_ENABLED", "true") == "true"
daemon["mcp"] = {"enabled": mcp_enabled}

password_hash = os.environ.get("PASEO_PASSWORD_HASH", "")
if password_hash:
    auth = daemon.setdefault("auth", {})
    if password_hash.startswith("__PLAINTEXT__"):
        auth["password"] = password_hash[len("__PLAINTEXT__"):]
    else:
        auth["password"] = password_hash
elif "auth" in daemon and "password" in daemon.get("auth", {}):
    pass  # preserve existing password
else:
    daemon.pop("auth", None)

path.write_text(json.dumps(config, indent=2) + "\n")
PYEOF
log_info "Paseo config written to $PASEO_CONFIG"

# Shell integration — paseo-daemon helper
FISH_FUNC_DIR="$HOME/.config/fish/functions"
mkdir -p "$FISH_FUNC_DIR"

cat > "${FISH_FUNC_DIR}/paseo_daemon.fish" << 'FISHEOF'
function paseo-daemon
    set -l args daemon start
    if test -n "$PASEO_HOME"
        set -a args --home "$PASEO_HOME"
    end
    paseo $args $argv
end
FISHEOF

if ! grep -q "# paseo-daemon (added by setup)" "$HOME/.bashrc" 2>/dev/null; then
cat >> "$HOME/.bashrc" << 'BASHEOF'

# paseo-daemon (added by setup)
paseo-daemon() {
  local args=("daemon" "start")
  if [[ -n "${PASEO_HOME:-}" ]]; then
    args+=(--home "$PASEO_HOME")
  fi
  paseo "${args[@]}" "$@"
}
BASHEOF
fi

log_info "paseo: done"
