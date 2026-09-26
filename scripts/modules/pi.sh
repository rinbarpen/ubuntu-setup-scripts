#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"
source "${SCRIPT_DIR}/../lib/api.sh"
source "${SCRIPT_DIR}/../lib/mcp.sh"

need_cmd npm
need_cmd python3

PI_CFG_DIR="$HOME/.pi/agent"
PI_SETTINGS="$PI_CFG_DIR/settings.json"
PI_MODELS="$PI_CFG_DIR/models.json"

# Node version check (pi requires >= 20.6.0)
_node_ver=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1 || echo "0")
if [[ "$_node_ver" -lt 20 ]]; then
  log_err "Pi requires Node.js >= 20.6.0. Current: $(node --version 2>/dev/null || echo 'not found')"
  log_err "Run the 'languages' module first to install a compatible Node version."
  exit 1
fi

# ---- Install pi CLI ------------------------------------------------
install_pi() {

if command -v pi &>/dev/null; then
  log_info "Pi already installed ($(command -v pi)), skipping npm install"
else
  log_info "Installing Pi Coding Agent..."
  npm install -g @mariozechner/pi-coding-agent
fi

mkdir -p "$PI_CFG_DIR"

# ---- OmniRoute provider ---------------------------------------------
PI_PROVIDER="omniroute"
PI_BASE_URL="http://localhost:20128/v1"
PI_API_KEY_ENV="OMNIROUTE_API_KEY"

# ---- Model selection ------------------------------------------------
PI_MODEL="omniroute/auto"
if [[ -f "$PI_SETTINGS" ]]; then
  _em=$(python3 -c "
import json
try:
    c = json.load(open('$PI_SETTINGS'))
    print(c.get('model', ''))
except: pass
" 2>/dev/null || echo "")
  [[ -n "$_em" ]] && PI_MODEL="$_em"
fi

if command -v whiptail &>/dev/null; then
  CHOICE=$(whiptail --title "Pi Model" --menu "Select OmniRoute model:" 16 70 6 \
    "omniroute/auto"       "OmniRoute Auto" \
    "omniroute/auto/coding" "OmniRoute Coding" \
    "omniroute/auto/fast"  "OmniRoute Fast" \
    "custom"               "Custom model ID" \
    3>&1 1>&2 2>&3) || CHOICE=""
  [[ -n "${CHOICE:-}" ]] && PI_MODEL="$CHOICE"
  [[ "$PI_MODEL" == "custom" ]] && { read -r -p "Enter custom model ID: " PI_MODEL; }
fi

export PI_PROVIDER PI_BASE_URL PI_API_KEY_ENV PI_MODEL

# ---- Write settings.json --------------------------------------------
python3 - "$PI_SETTINGS" << 'PYEOF'
import json, os, pathlib, sys

path = pathlib.Path(sys.argv[1])

try:
    config = json.loads(path.read_text())
except Exception:
    config = {}

provider = os.environ.get("PI_PROVIDER", "omniroute")
model    = os.environ.get("PI_MODEL", "omniroute/auto")
base_url = os.environ.get("PI_BASE_URL", "https://api.deepseek.com/v1")
key_env  = os.environ.get("PI_API_KEY_ENV", "DEEPSEEK_API_KEY")

config["provider"] = provider
config["baseUrl"]  = base_url
config["model"]    = model

# Pi expects {env:VAR_NAME} syntax for API keys in config
if key_env:
    config["apiKey"] = f"{{env:{key_env}}}"

config["maxTokens"] = 1000000
config.setdefault("cache", {})["consistentPrompt"] = True
config.setdefault("autoLoad", ["CLAUDE.md", "AGENTS.md"])

path.write_text(json.dumps(config, indent=2) + "\n")
print(f"pi settings written to {path}")
PYEOF

log_info "Pi settings written to $PI_SETTINGS (OmniRoute: $PI_BASE_URL; start with rinbake omniroute start if needed)"

# ---- Write models.json (model registry) -----------------------------
python3 - "$PI_MODELS" "$PI_PROVIDER" "$PI_MODEL" << 'PYEOF'
import json, os, pathlib, sys

path     = pathlib.Path(sys.argv[1])
provider = sys.argv[2]
model    = sys.argv[3]

models = [
    {"id": "auto", "name": "OmniRoute Auto", "provider": "omniroute"},
    {"id": "auto/coding", "name": "OmniRoute Coding", "provider": "omniroute"},
    {"id": "auto/fast", "name": "OmniRoute Fast", "provider": "omniroute"},
]

path.write_text(json.dumps({"models": models}, indent=2) + "\n")
PYEOF

log_info "Pi model registry written to $PI_MODELS"

# ---- MCP Toolkits ---------------------------------------------------
SCENARIOS=$(mcp_select_scenarios "Pi MCP Toolkits")
if [[ -n "$SCENARIOS" ]]; then
  CREDS=$(mcp_collect_credentials "$SCENARIOS")
  mcp_write_json "$PI_SETTINGS" "mcpServers" "$SCENARIOS" "$CREDS"
  log_info "Pi MCP servers written to $PI_SETTINGS"
fi

# ---- Shell helper functions -----------------------------------------
FISH_FUNC_DIR="$HOME/.config/fish/functions"
mkdir -p "$FISH_FUNC_DIR"

cat > "${FISH_FUNC_DIR}/pi_env.fish" << 'FEOF'
function pi_env
    set -l key_file ~/.config/rinbarpen/api-keys.env
    if test -f $key_file
        bass source $key_file
        echo "pi environment loaded from $key_file"
    else
        echo "No api-keys.env found at $key_file"
        return 1
    end
end
FEOF
log_info "Fish function: pi_env"

if ! grep -q "# pi-env (added by setup)" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" << 'BASHEOF'

# pi-env (added by setup)
pi-env() {
  local f="$HOME/.config/rinbarpen/api-keys.env"
  if [[ -f "$f" ]]; then
    # shellcheck source=/dev/null
    source "$f"
    echo "pi environment loaded from $f"
  else
    echo "No api-keys.env found at $f"
    return 1
  fi
}
BASHEOF
  log_info "Bash function: pi-env"
fi

# ---- Marker file ----------------------------------------------------
echo "pi" > "$PI_CFG_DIR/.managed-by"
log_info "pi: done"
}

install_pi "$@"
