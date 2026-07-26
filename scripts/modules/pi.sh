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

# ---- Provider selection ---------------------------------------------
PI_PROVIDER="deepseek"
PI_BASE_URL=""
PI_API_KEY_ENV="DEEPSEEK_API_KEY"

# Read existing config if available
if [[ -f "$PI_SETTINGS" ]]; then
  _ep=$(python3 -c "
import json
try:
    c = json.load(open('$PI_SETTINGS'))
    print(c.get('provider', ''))
except: pass
" 2>/dev/null || echo "")
  [[ -n "$_ep" ]] && PI_PROVIDER="$_ep"
fi

if command -v whiptail &>/dev/null; then
  _prov_info="当前: ${PI_PROVIDER}"
  CHOICE=$(whiptail --title "Pi Provider" --menu "Select default provider:\n${_prov_info}" 22 70 10 \
    "deepseek"    "DeepSeek (api.deepseek.com)" \
    "openai"      "OpenAI (api.openai.com)" \
    "openrouter"  "OpenRouter (openrouter.ai)" \
    "aihubmix"    "AIHubMix (aihubmix.com)" \
    "anthropic"   "Anthropic (api.anthropic.com)" \
    "google"      "Google Gemini" \
    "ollama"      "Ollama (local)" \
    "custom"      "Custom provider" \
    3>&1 1>&2 2>&3) || CHOICE=""
  [[ -n "$CHOICE" ]] && PI_PROVIDER="$CHOICE"
fi

case "$PI_PROVIDER" in
  deepseek)
    PI_BASE_URL="https://api.deepseek.com/v1"
    PI_API_KEY_ENV="DEEPSEEK_API_KEY"
    api_key_get "$PI_API_KEY_ENV" "DeepSeek API Key" true
    ;;
  openai)
    PI_BASE_URL="https://api.openai.com/v1"
    PI_API_KEY_ENV="OPENAI_API_KEY"
    api_key_get "$PI_API_KEY_ENV" "OpenAI API Key" true
    ;;
  openrouter)
    PI_BASE_URL="https://openrouter.ai/api/v1"
    PI_API_KEY_ENV="OPENROUTER_API_KEY"
    api_key_get "$PI_API_KEY_ENV" "OpenRouter API Key" true
    ;;
  aihubmix)
    PI_BASE_URL="https://aihubmix.com/v1"
    PI_API_KEY_ENV="AIHUBMIX_API_KEY"
    api_key_get "$PI_API_KEY_ENV" "AIHubMix API Key" true
    ;;
  anthropic)
    PI_BASE_URL="https://api.anthropic.com/v1"
    PI_API_KEY_ENV="ANTHROPIC_API_KEY"
    api_key_get "$PI_API_KEY_ENV" "Anthropic API Key" true
    ;;
  google)
    PI_BASE_URL="https://generativelanguage.googleapis.com/v1beta"
    PI_API_KEY_ENV="GOOGLE_API_KEY"
    api_key_get "$PI_API_KEY_ENV" "Google API Key" true
    ;;
  ollama)
    PI_BASE_URL="http://localhost:11434/v1"
    PI_API_KEY_ENV=""
    ;;
  custom)
    read -r -p "API base URL: " PI_BASE_URL
    read -r -p "API key env var name (leave empty if none): " PI_API_KEY_ENV
    if [[ -n "$PI_API_KEY_ENV" ]]; then
      api_key_get "$PI_API_KEY_ENV" "API Key for $PI_PROVIDER" true
    fi
    ;;
esac

# ---- Model selection ------------------------------------------------
PI_MODEL="deepseek-v4-flash"
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
  case "$PI_PROVIDER" in
    deepseek)
      _model_info="当前: ${PI_MODEL}"
      CHOICE=$(whiptail --title "Pi Model" --menu "Select model:\n${_model_info}" 18 70 7 \
        "deepseek-v4-flash"  "DeepSeek V4 Flash (fast & cheap)" \
        "deepseek-v4-pro"    "DeepSeek V4 Pro (enhanced)" \
        "deepseek-chat"      "DeepSeek V3 Chat" \
        "deepseek-reasoner"  "DeepSeek Reasoner (R1)" \
        "custom"             "Custom model ID" \
        3>&1 1>&2 2>&3) || CHOICE=""
      ;;
    openai)
      _model_info="当前: ${PI_MODEL}"
      CHOICE=$(whiptail --title "Pi Model" --menu "Select model:\n${_model_info}" 18 70 7 \
        "gpt-5.5"       "GPT-5.5" \
        "gpt-4o"        "GPT-4o" \
        "gpt-4o-mini"   "GPT-4o Mini" \
        "o4-mini"       "o4-mini (reasoning)" \
        "custom"        "Custom model ID" \
        3>&1 1>&2 2>&3) || CHOICE=""
      ;;
    openrouter)
      _model_info="当前: ${PI_MODEL}"
      CHOICE=$(whiptail --title "Pi Model" --menu "Select model:\n${_model_info}" 20 70 8 \
        "openai/gpt-5.5"                    "GPT-5.5" \
        "openai/gpt-4o"                     "GPT-4o" \
        "anthropic/claude-sonnet-4-20250514" "Claude Sonnet 4" \
        "anthropic/claude-opus-4-20250514"   "Claude Opus 4" \
        "deepseek/deepseek-v4-pro"           "DeepSeek V4 Pro" \
        "custom"                             "Custom model ID" \
        3>&1 1>&2 2>&3) || CHOICE=""
      ;;
    *)
      read -r -p "Model ID [${PI_MODEL}]: " _input
      [[ -n "$_input" ]] && PI_MODEL="$_input"
      CHOICE=""
      ;;
  esac
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

provider = os.environ.get("PI_PROVIDER", "deepseek")
model    = os.environ.get("PI_MODEL", "deepseek-v4-flash")
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

log_info "Pi settings written to $PI_SETTINGS"

# ---- Write models.json (model registry) -----------------------------
python3 - "$PI_MODELS" "$PI_PROVIDER" "$PI_MODEL" << 'PYEOF'
import json, os, pathlib, sys

path     = pathlib.Path(sys.argv[1])
provider = sys.argv[2]
model    = sys.argv[3]

models = []
if provider == "deepseek":
    models = [
        {"id": "deepseek-v4-flash", "name": "DeepSeek V4 Flash", "provider": "deepseek"},
        {"id": "deepseek-v4-pro",   "name": "DeepSeek V4 Pro",   "provider": "deepseek"},
        {"id": "deepseek-chat",     "name": "DeepSeek V3 Chat",  "provider": "deepseek"},
    ]
elif provider == "openai":
    models = [
        {"id": "gpt-5.5",     "name": "GPT-5.5",      "provider": "openai"},
        {"id": "gpt-4o",      "name": "GPT-4o",       "provider": "openai"},
        {"id": "gpt-4o-mini", "name": "GPT-4o Mini",  "provider": "openai"},
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
