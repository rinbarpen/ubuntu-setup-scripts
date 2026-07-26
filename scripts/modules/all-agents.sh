#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"
source "${SCRIPT_DIR}/../lib/api.sh"
source "${SCRIPT_DIR}/../lib/mcp.sh"

need_cmd npm
need_cmd python3

# ------------------------------------------------------------------
# all-agents: Unified installer & configurator for 5 AI coding agents
#
# Phase 1: Agent selection (whiptail checklist)
# Phase 2: Preset detection & loading
# Phase 3: Shared provider/model selection (if no preset)
# Phase 4: Per-agent customization
# Phase 5: Unified MCP scenario selection
# Phase 6: Config generation (Python heredocs per agent)
# Phase 7: Shell functions + summary
# Phase 8: Save as preset (optional)
# ------------------------------------------------------------------

PRESET_DIR="${HOME}/.config/rinbarpen/agent-presets"
declare -A AGENT_SELECTED

# ---- Helper: read JSON string value via Python ----------------------
_json_val() {
  local file="$1" key="$2" default="${3:-}"
  python3 -c "
import json,sys
try:
    c = json.load(open('$file'))
    parts = '$key'.split('.')
    for p in parts:
        c = c.get(p, {}) if isinstance(c, dict) else {}
    print(c if isinstance(c, str) else '')
except: print('$default')
" 2>/dev/null || echo "$default"
}

_json_bool() {
  local file="$1" key="$2" default="${3:-false}"
  python3 -c "
import json,sys
try:
    c = json.load(open('$file'))
    parts = '$key'.split('.')
    for p in parts:
        c = c.get(p, {}) if isinstance(c, dict) else {}
    print('true' if c == True else 'false')
except: print('$default')
" 2>/dev/null || echo "$default"
}

# ---- Phase 1: Agent Selection ---------------------------------------
select_agents() {
  if ! command -v whiptail &>/dev/null; then
    # Non-interactive: configure all
    AGENT_SELECTED[opencode]=1
    AGENT_SELECTED[codex]=1
    AGENT_SELECTED[claude-code]=1
    AGENT_SELECTED[pi]=1
    AGENT_SELECTED[omp]=1
    return
  fi

  local choices
  choices=$(whiptail --title "Agent Configuration" --checklist \
    "Select agents to configure (SPACE to toggle):" 16 60 5 \
    "opencode"    "opencode CLI + MCP"                ON \
    "codex"       "Codex CLI + MCP"                   ON \
    "claude-code" "Claude Code + MCP"                 ON \
    "pi"          "Pi Coding Agent (minimal)"          ON \
    "omp"         "Oh-My-Pi (feature-rich)"            ON \
    3>&1 1>&2 2>&3) || choices=""

  local sel
  sel=$(echo "$choices" | tr -d '"')
  for agent in "opencode" "codex" "claude-code" "pi" "omp"; do
    if echo "$sel" | grep -Fqw "$agent"; then
      AGENT_SELECTED[$agent]=1
    fi
  done
}

# ---- Phase 2: Preset Detection & Loading ----------------------------
detect_and_load_preset() {
  mkdir -p "$PRESET_DIR"

  local preset_files
  preset_files=$(ls "$PRESET_DIR"/*.json 2>/dev/null || echo "")

  if [[ -z "$preset_files" ]]; then
    log_info "No presets found at $PRESET_DIR — using interactive configuration"
    PRESET_ACTIVE="false"
    return 0
  fi

  if ! command -v whiptail &>/dev/null; then
    # Non-interactive: try active.json first, then first available
    if [[ -f "$PRESET_DIR/active.json" ]]; then
      load_preset_file "$PRESET_DIR/active.json"
      return 0
    fi
    local first
    first=$(ls "$PRESET_DIR"/*.json 2>/dev/null | head -1)
    [[ -n "$first" ]] && load_preset_file "$first"
    return 0
  fi

  # Build menu items from available presets
  local menu_args=()
  local idx=1
  local preset_names=()
  for pf in "$PRESET_DIR"/*.json; do
    [[ ! -f "$pf" ]] && continue
    local name desc
    name=$(_json_val "$pf" "name" "$(basename "$pf" .json)")
    desc=$(_json_val "$pf" "description" "user preset")
    menu_args+=("$idx" "$name — $desc")
    preset_names+=("$pf")
    ((idx++))
  done

  if [[ ${#menu_args[@]} -eq 0 ]]; then
    log_info "No valid presets found"
    PRESET_ACTIVE="false"
    return 0
  fi

  menu_args+=("0" "Skip — configure interactively")
  preset_names+=("")

  local choice
  choice=$(whiptail --title "Agent Presets" --menu \
    "Select a preset to load (or skip for interactive setup):" \
    20 75 "$(( ${#preset_names[@]} ))" \
    "${menu_args[@]}" \
    3>&1 1>&2 2>&3) || choice="0"

  if [[ "$choice" == "0" || -z "$choice" ]]; then
    PRESET_ACTIVE="false"
    return 0
  fi

  local preset_file="${preset_names[$((choice - 1))]}"
  load_preset_file "$preset_file"
}

load_preset_file() {
  local preset_file="$1"
  log_info "Loading preset: $(basename "$preset_file")"

  # Validate JSON and export all values
  python3 - "$preset_file" << 'PYEOF'
import json, os, sys

with open(sys.argv[1]) as f:
    p = json.load(f)

print(f"export PRESET_ACTIVE=true")
print(f"export PRESET_NAME=\"{p.get('name', 'unnamed')}\"")

shared = p.get("provider", {})
if shared.get("defaultProvider"):
    print(f"export PRESET_SHARED_DEFAULT_PROVIDER=\"{shared['defaultProvider']}\"")

agents = p.get("agents", {})
for agent_name, cfg in agents.items():
    env_prefix = agent_name.upper().replace("-", "_")
    enabled = cfg.get("enabled", True)
    print(f"export PRESET_{env_prefix}_INSTALL={'true' if enabled else 'false'}")
    if cfg.get("model"):
        print(f"export PRESET_{env_prefix}_MODEL=\"{cfg['model']}\"")
    if cfg.get("planModel"):
        print(f"export PRESET_{env_prefix}_PLAN_MODEL=\"{cfg['planModel']}\"")

    # Claude Code specific
    if cfg.get("permissionMode"):
        print(f"export PRESET_{env_prefix}_PERMISSION_MODE=\"{cfg['permissionMode']}\"")

    # Codex specific
    if cfg.get("reasoningEffort"):
        print(f"export PRESET_{env_prefix}_REASONING_EFFORT=\"{cfg['reasoningEffort']}\"")
    if cfg.get("approvalPolicy"):
        print(f"export PRESET_{env_prefix}_APPROVAL_POLICY=\"{cfg['approvalPolicy']}\"")

    # Pi specific
    if cfg.get("provider"):
        print(f"export PRESET_{env_prefix}_PROVIDER=\"{cfg['provider']}\"")
    if cfg.get("maxTokens"):
        print(f"export PRESET_{env_prefix}_MAX_TOKENS=\"{cfg['maxTokens']}\"")

    # omp specific
    features = cfg.get("features", {})
    feat_list = []
    if features.get("hashAnchoredEdits"): feat_list.append("hashAnchoredEdits")
    if features.get("snapcompact"): feat_list.append("snapcompact")
    if features.get("lsp"): feat_list.append("lsp")
    if features.get("dap"): feat_list.append("dap")
    if features.get("subagentSystem"): feat_list.append("subagentSystem")
    if feat_list:
        print(f"export PRESET_{env_prefix}_FEATURES=\"{','.join(feat_list)}\"")

mcp = p.get("mcp", {})
scenarios = mcp.get("scenarios", [])
if scenarios:
    print(f"export PRESET_MCP_SCENARIOS=\"{' '.join(scenarios)}\"")
PYEOF

  # Source the exported vars
  eval "$(python3 - "$preset_file" << 'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    p = json.load(f)

print(f"PRESET_ACTIVE=true")
shared = p.get("provider", {})
if shared.get("defaultProvider"):
    print(f"PRESET_SHARED_DEFAULT_PROVIDER='{shared['defaultProvider']}'")

agents = p.get("agents", {})
for agent_name, cfg in agents.items():
    env_prefix = agent_name.upper().replace("-", "_")
    enabled = cfg.get("enabled", True)
    print(f"PRESET_{env_prefix}_INSTALL={'true' if enabled else 'false'}")
    if cfg.get("model"):
        print(f"PRESET_{env_prefix}_MODEL='{cfg['model']}'")
    if cfg.get("planModel"):
        print(f"PRESET_{env_prefix}_PLAN_MODEL='{cfg['planModel']}'")
    if cfg.get("permissionMode"):
        print(f"PRESET_{env_prefix}_PERMISSION_MODE='{cfg['permissionMode']}'")
    if cfg.get("reasoningEffort"):
        print(f"PRESET_{env_prefix}_REASONING_EFFORT='{cfg['reasoningEffort']}'")
    if cfg.get("approvalPolicy"):
        print(f"PRESET_{env_prefix}_APPROVAL_POLICY='{cfg['approvalPolicy']}'")
    if cfg.get("provider"):
        print(f"PRESET_{env_prefix}_PROVIDER='{cfg['provider']}'")
    if cfg.get("maxTokens"):
        print(f"PRESET_{env_prefix}_MAX_TOKENS='{cfg['maxTokens']}'")
    features = cfg.get("features", {})
    feat_list = []
    if features.get("hashAnchoredEdits"): feat_list.append("hashAnchoredEdits")
    if features.get("snapcompact"): feat_list.append("snapcompact")
    if features.get("lsp"): feat_list.append("lsp")
    if features.get("dap"): feat_list.append("dap")
    if features.get("subagentSystem"): feat_list.append("subagentSystem")
    if feat_list:
        print(f"PRESET_{env_prefix}_FEATURES='{','.join(feat_list)}'")

mcp = p.get("mcp", {})
scenarios = mcp.get("scenarios", [])
if scenarios:
    print(f"PRESET_MCP_SCENARIOS='{' '.join(scenarios)}'")
PYEOF
)"
  PRESET_ACTIVE="true"
  log_info "Preset loaded: $(basename "$preset_file")"
}

# ---- Phase 3: Shared Provider/Model Selection -----------------------
collect_shared_config() {
  if [[ "${PRESET_ACTIVE:-false}" == "true" ]]; then
    log_info "Using preset values — skipping shared config prompts"
    SHARED_PROVIDER="${PRESET_SHARED_DEFAULT_PROVIDER:-deepseek}"
    export SHARED_PROVIDER
    return 0
  fi

  SHARED_PROVIDER="deepseek"

  if command -v whiptail &>/dev/null; then
    SHARED_PROVIDER=$(whiptail --title "Default Provider" --menu \
      "Select the default provider for all agents:" 20 70 8 \
      "deepseek"   "DeepSeek (api.deepseek.com)" \
      "openai"     "OpenAI (api.openai.com)" \
      "openrouter" "OpenRouter (openrouter.ai)" \
      "aihubmix"   "AIHubMix (aihubmix.com)" \
      "anthropic"  "Anthropic (api.anthropic.com)" \
      "custom"     "Custom provider" \
      3>&1 1>&2 2>&3) || SHARED_PROVIDER="deepseek"
  fi

  export SHARED_PROVIDER
  log_info "Default provider: $SHARED_PROVIDER"

  # Collect API keys for the selected provider
  case "$SHARED_PROVIDER" in
    deepseek)   api_key_get "DEEPSEEK_API_KEY" "DeepSeek API Key" true ;;
    openai)     api_key_get "OPENAI_API_KEY" "OpenAI API Key" true ;;
    openrouter) api_key_get "OPENROUTER_API_KEY" "OpenRouter API Key" true ;;
    aihubmix)   api_key_get "AIHUBMIX_API_KEY" "AIHubMix API Key" true ;;
    anthropic)  api_key_get "ANTHROPIC_API_KEY" "Anthropic API Key" true ;;
  esac
}

# ---- Phase 4: Per-Agent Customization --------------------------------
# Each function is called only if the corresponding AGENT_SELECTED is set

configure_claude_code() {
  local model="${PRESET_CLAUDE_CODE_MODEL:-deepseek-v4-flash}"
  local plan_model="${PRESET_CLAUDE_CODE_PLAN_MODEL:-deepseek-v4-pro}"
  local perm_mode="${PRESET_CLAUDE_CODE_PERMISSION_MODE:-acceptEdits}"

  CLAUDE_SETTINGS="$HOME/.claude/settings.json"
  mkdir -p "$(dirname "$CLAUDE_SETTINGS")"

  # Install Claude Code if not present
  if ! command -v claude &>/dev/null; then
    log_info "Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code
  else
    log_info "Claude Code already installed"
  fi

  # If no preset, prompt for model and permission mode
  if [[ "${PRESET_ACTIVE:-false}" != "true" ]] && command -v whiptail &>/dev/null; then
    model=$(whiptail --title "Claude Code Model" --menu "Select chat model:" 18 70 6 \
      "deepseek-v4-flash" "DeepSeek V4 Flash (fast)" \
      "deepseek-v4-pro"   "DeepSeek V4 Pro (enhanced)" \
      "openai/gpt-5.5"    "GPT-5.5" \
      "custom"            "Custom model" \
      3>&1 1>&2 2>&3) || model="deepseek-v4-flash"
    [[ "$model" == "custom" ]] && { read -r -p "Model ID: " model; }

    perm_mode=$(whiptail --title "Permission Mode" --menu "Select permission mode:" 14 60 3 \
      "acceptEdits" "Auto-accept edits" \
      "default"     "Ask every time" \
      "bypass"      "Bypass all checks" \
      3>&1 1>&2 2>&3) || perm_mode="acceptEdits"
  fi

  export CLAUDE_MODEL="$model"
  export CLAUDE_PLAN_MODEL="$plan_model"
  export PERM_MODE="$perm_mode"

  # Write settings.json
  python3 - "$CLAUDE_SETTINGS" << 'PYEOF'
import json, os, pathlib, sys

path = pathlib.Path(sys.argv[1])
model = os.environ.get("CLAUDE_MODEL", "deepseek-v4-flash")

try:
    settings = json.loads(path.read_text())
except Exception:
    settings = {}

settings["model"] = model

env = settings.setdefault("env", {})
env.setdefault("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "1")
env.setdefault("CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK", "1")
env.setdefault("CLAUDE_CODE_ATTRIBUTION_HEADER", "0")
env.setdefault("ENABLE_TOOL_SEARCH", "1")
env.setdefault("DISABLE_EXTRA_USAGE_COMMAND", "1")
env.setdefault("ANTHROPIC_MODEL", model)
env.setdefault("ANTHROPIC_DEFAULT_SONNET_MODEL", model)
env.setdefault("ANTHROPIC_DEFAULT_HAIKU_MODEL", "deepseek-v4-flash")
env.setdefault("CLAUDE_CODE_SUBAGENT_MODEL", model)
env.setdefault("CLAUDE_CODE_MAX_OUTPUT_TOKENS", "1000000")
env.setdefault("CLAUDE_CODE_EFFORT_LEVEL", "max")

plan_model = os.environ.get("CLAUDE_PLAN_MODEL", "")
if plan_model:
    env["ANTHROPIC_DEFAULT_OPUS_MODEL"] = plan_model

perm = settings.setdefault("permissions", {})
perm["defaultMode"] = os.environ.get("PERM_MODE", "acceptEdits")

path.write_text(json.dumps(settings, indent=2) + "\n")
PYEOF
  log_info "Claude Code settings written to $CLAUDE_SETTINGS"
}

configure_codex() {
  local model="${PRESET_CODEX_MODEL:-deepseek-v4-pro}"
  local plan_model="${PRESET_CODEX_PLAN_MODEL:-deepseek-v4-pro}"
  local reasoning="${PRESET_CODEX_REASONING_EFFORT:-medium}"
  local plan_reasoning="${PRESET_CODEX_PLAN_REASONING_EFFORT:-xhigh}"
  local approval="${PRESET_CODEX_APPROVAL_POLICY:-on-request}"

  CODEX_CFG="$HOME/.codex/config.toml"
  mkdir -p "$(dirname "$CODEX_CFG")"

  if ! command -v codex &>/dev/null; then
    log_info "Installing Codex..."
    npm install -g @openai/codex
  else
    log_info "Codex already installed"
  fi

  # If no preset, prompt for settings
  if [[ "${PRESET_ACTIVE:-false}" != "true" ]] && command -v whiptail &>/dev/null; then
    model=$(whiptail --title "Codex Model" --menu "Select chat model:" 18 70 6 \
      "deepseek-v4-pro"   "DeepSeek V4 Pro" \
      "deepseek-v4-flash" "DeepSeek V4 Flash" \
      "gpt-5.5"           "GPT-5.5" \
      "gpt-4o"            "GPT-4o" \
      "custom"            "Custom model" \
      3>&1 1>&2 2>&3) || model="deepseek-v4-pro"
    [[ "$model" == "custom" ]] && { read -r -p "Model ID: " model; }

    approval=$(whiptail --title "Codex Approval" --menu "Approval policy:" 14 60 3 \
      "on-request" "Ask for approval" \
      "never"      "Never approve automatically" \
      "always"     "Always approve" \
      3>&1 1>&2 2>&3) || approval="on-request"
  fi

  export CODEX_MODEL="$model"
  export CODEX_PLAN_MODEL="$plan_model"
  export CODEX_REASONING="$reasoning"
  export CODEX_PLAN_REASONING="$plan_reasoning"
  export CODEX_APPROVAL="$approval"

  # Write config.toml
  python3 - "$CODEX_CFG" << 'PYEOF'
import os, re, sys

path = sys.argv[1]

try:
    with open(path) as f:
        content = f.read()
except Exception:
    content = "[features]\nmemories = false\nhooks = true\nundo = false\n"

model = os.environ.get("CODEX_MODEL", "deepseek-v4-pro")
plan  = os.environ.get("CODEX_PLAN_MODEL", "deepseek-v4-pro")
reasoning = os.environ.get("CODEX_REASONING", "medium")
plan_reasoning = os.environ.get("CODEX_PLAN_REASONING", "xhigh")
approval = os.environ.get("CODEX_APPROVAL", "on-request")

# Update or add managed keys
def set_key(ct, key, val):
    pattern = rf'^{re.escape(key)}\s*=.*$'
    if re.search(pattern, ct, re.MULTILINE):
        return re.sub(pattern, f'{key} = "{val}"', ct, flags=re.MULTILINE)
    else:
        return ct.rstrip() + f'\n{key} = "{val}"\n'

content = set_key(content, "model", model)
content = set_key(content, "plan_model", plan)
content = set_key(content, "model_reasoning_effort", reasoning)
content = set_key(content, "plan_mode_reasoning_effort", plan_reasoning)
content = set_key(content, "approval_policy", approval)

with open(path, 'w') as f:
    f.write(content)
PYEOF
  log_info "Codex settings written to $CODEX_CFG"
}

configure_opencode() {
  local model="${PRESET_OPENCODE_MODEL:-deepseek/deepseek-v4-flash}"
  local plan_model="${PRESET_OPENCODE_PLAN_MODEL:-openai/gpt-5.5}"

  OPEN_CODE_CFG="$HOME/.config/opencode/opencode.json"
  mkdir -p "$(dirname "$OPEN_CODE_CFG")"

  log_info "Installing opencode..."
  npm install -g opencode-ai 2>/dev/null || log_info "opencode install attempted (may already exist)"

  if [[ "${PRESET_ACTIVE:-false}" != "true" ]] && command -v whiptail &>/dev/null; then
    model=$(whiptail --title "opencode Model" --menu "Select chat model:" 20 70 8 \
      "deepseek/deepseek-v4-flash" "DeepSeek V4 Flash" \
      "deepseek/deepseek-v4-pro"   "DeepSeek V4 Pro" \
      "openai/gpt-5.5"             "GPT-5.5" \
      "openai/gpt-4o"              "GPT-4o" \
      "openrouter/anthropic/claude-sonnet-4-20250514" "Claude Sonnet 4" \
      "custom"                     "Custom model" \
      3>&1 1>&2 2>&3) || model="deepseek/deepseek-v4-flash"
    [[ "$model" == "custom" ]] && { read -r -p "Model (provider/model): " model; }
  fi

  export DEFAULT_MODEL="$model"
  export PLAN_MODEL="$plan_model"

  RELAY_PROVIDER="none"
  RELAY_BASE_URL=""
  RELAY_KEY_NAME=""

  if [[ "${PRESET_ACTIVE:-false}" != "true" ]] && command -v whiptail &>/dev/null; then
    RELAY_PROVIDER=$(whiptail --title "opencode Relay" --menu \
      "Relay for OpenAI/GPT models:" 14 60 4 \
      "none"       "Direct OpenAI API" \
      "openrouter" "OpenRouter" \
      "aihubmix"   "AIHubMix" \
      "custom"     "Custom relay" \
      3>&1 1>&2 2>&3) || RELAY_PROVIDER="none"

    case "$RELAY_PROVIDER" in
      openrouter)
        RELAY_BASE_URL="https://openrouter.ai/api/v1"
        RELAY_KEY_NAME="OPENROUTER_API_KEY"
        api_key_get "$RELAY_KEY_NAME" "OpenRouter API Key" true
        ;;
      aihubmix)
        RELAY_BASE_URL="https://aihubmix.com/v1"
        RELAY_KEY_NAME="AIHUBMIX_API_KEY"
        api_key_get "$RELAY_KEY_NAME" "AIHubMix API Key" true
        ;;
      custom)
        read -r -p "Relay base URL: " RELAY_BASE_URL
        read -r -p "API key env var name: " RELAY_KEY_NAME
        api_key_get "$RELAY_KEY_NAME" "API Key for relay" true
        ;;
    esac
  fi
  export RELAY_PROVIDER RELAY_BASE_URL RELAY_KEY_NAME

  python3 - "$OPEN_CODE_CFG" << 'PYEOF'
import json, os, pathlib, sys

path = pathlib.Path(sys.argv[1])

try:
    config = json.loads(path.read_text())
except Exception:
    config = {}

config["$schema"] = "https://opencode.ai/config.json"
config["model"] = os.environ.get("DEFAULT_MODEL", "deepseek/deepseek-v4-flash")

provider = config.setdefault("provider", {})
provider["deepseek"] = {"npm": "@ai-sdk/deepseek", "options": {"apiKey": "{env:DEEPSEEK_API_KEY}"}}

openai_opts = {"apiKey": "{env:OPENAI_API_KEY}"}
relay_base_url = os.environ.get("RELAY_BASE_URL", "")
if relay_base_url:
    openai_opts["baseURL"] = relay_base_url
provider["openai"] = {"npm": "@ai-sdk/openai", "options": openai_opts}
provider["openrouter"] = {"npm": "@ai-sdk/openai", "options": {"apiKey": "{env:OPENROUTER_API_KEY}", "baseURL": "https://openrouter.ai/api/v1"}}
provider["aihubmix"] = {"npm": "@ai-sdk/openai", "options": {"apiKey": "{env:AIHUBMIX_API_KEY}", "baseURL": "https://aihubmix.com/v1"}}

agent = config.setdefault("agent", {})
plan = agent.setdefault("plan", {})
plan["model"] = os.environ.get("PLAN_MODEL", "openai/gpt-5.5")
plan.setdefault("options", {})["reasoningEffort"] = "xhigh"

perm = config.setdefault("permission", {})
perm["edit"] = "ask"
perm["bash"] = "ask"
perm["external_directory"] = "ask"

path.write_text(json.dumps(config, indent=2) + "\n")
PYEOF
  log_info "opencode settings written to $OPEN_CODE_CFG"
}

configure_pi() {
  local model="${PRESET_PI_MODEL:-deepseek-v4-flash}"
  local provider="${PRESET_PI_PROVIDER:-deepseek}"
  local max_tokens="${PRESET_PI_MAX_TOKENS:-1000000}"

  PI_CFG_DIR="$HOME/.pi/agent"
  PI_SETTINGS="$PI_CFG_DIR/settings.json"
  mkdir -p "$PI_CFG_DIR"

  if ! command -v pi &>/dev/null; then
    log_info "Installing Pi..."
    npm install -g @mariozechner/pi-coding-agent
  else
    log_info "Pi already installed"
  fi

  case "$provider" in
    deepseek)   api_key_get "DEEPSEEK_API_KEY" "DeepSeek API Key" true ;;
    openai)     api_key_get "OPENAI_API_KEY" "OpenAI API Key" true ;;
    openrouter) api_key_get "OPENROUTER_API_KEY" "OpenRouter API Key" true ;;
    anthropic)  api_key_get "ANTHROPIC_API_KEY" "Anthropic API Key" true ;;
  esac

  export PI_PROVIDER="$provider" PI_MODEL="$model" PI_MAX_TOKENS="$max_tokens"

  python3 - "$PI_SETTINGS" << 'PYEOF'
import json, os, pathlib, sys

path = pathlib.Path(sys.argv[1])
provider = os.environ.get("PI_PROVIDER", "deepseek")
model    = os.environ.get("PI_MODEL", "deepseek-v4-flash")

base_urls = {
    "deepseek": "https://api.deepseek.com/v1",
    "openai": "https://api.openai.com/v1",
    "openrouter": "https://openrouter.ai/api/v1",
    "anthropic": "https://api.anthropic.com/v1",
}
key_envs = {
    "deepseek": "DEEPSEEK_API_KEY",
    "openai": "OPENAI_API_KEY",
    "openrouter": "OPENROUTER_API_KEY",
    "anthropic": "ANTHROPIC_API_KEY",
}

try:
    config = json.loads(path.read_text())
except Exception:
    config = {}

config["provider"] = provider
config["baseUrl"]  = base_urls.get(provider, "")
config["model"]    = model
config["maxTokens"] = 1000000
config.setdefault("cache", {})["consistentPrompt"] = True
config.setdefault("autoLoad", ["CLAUDE.md", "AGENTS.md"])

key_env = key_envs.get(provider, "")
if key_env:
    config["apiKey"] = f"{{env:{key_env}}}"

path.write_text(json.dumps(config, indent=2) + "\n")
PYEOF
  log_info "Pi settings written to $PI_SETTINGS"
}

configure_omp() {
  local model="${PRESET_OMP_MODEL:-deepseek-v4-pro}"
  local provider="${PRESET_OMP_PROVIDER:-deepseek}"
  local feats="${PRESET_OMP_FEATURES:-hashAnchoredEdits,snapcompact}"

  OMP_CFG_DIR="$HOME/.pi/agent"
  OMP_SETTINGS="$OMP_CFG_DIR/settings.json"
  mkdir -p "$OMP_CFG_DIR"

  if ! command -v omp &>/dev/null; then
    log_info "Installing omp..."
    npm install -g oh-my-pi 2>/dev/null || log_info "omp install attempted (may already exist)"
  else
    log_info "omp already installed"
  fi

  # Parse features from comma-separated list
  local hash_edits="true" snapcompact="true" lsp="false" dap="false" subagents="false"
  for f in ${feats//,/ }; do
    case "$f" in
      hashAnchoredEdits) hash_edits="true" ;;
      snapcompact)       snapcompact="true" ;;
      lsp)               lsp="true" ;;
      dap)               dap="true" ;;
      subagentSystem)    subagents="true" ;;
    esac
  done

  export OMP_PROVIDER="$provider" OMP_MODEL="$model"
  export OMP_HASH_EDITS="$hash_edits" OMP_SNAPCOMPACT="$snapcompact"
  export OMP_LSP="$lsp" OMP_DAP="$dap" OMP_SUBAGENTS="$subagents"

  python3 - "$OMP_SETTINGS" << 'PYEOF'
import json, os, pathlib, sys

path = pathlib.Path(sys.argv[1])

try:
    config = json.loads(path.read_text())
except Exception:
    config = {}

provider = os.environ.get("OMP_PROVIDER", "")
model    = os.environ.get("OMP_MODEL", "")
if provider:
    config["provider"] = provider
if model:
    config["model"] = model

config["features"] = {
    "hashAnchoredEdits": os.environ.get("OMP_HASH_EDITS", "true") == "true",
    "snapcompact":       os.environ.get("OMP_SNAPCOMPACT", "true") == "true",
    "lsp":               os.environ.get("OMP_LSP", "false") == "true",
    "dap":               os.environ.get("OMP_DAP", "false") == "true",
    "subagentSystem":    os.environ.get("OMP_SUBAGENTS", "false") == "true",
}
config.setdefault("cache", {}).update({
    "hashAnchoredEdits": config["features"]["hashAnchoredEdits"],
    "consistentSystemPrompts": True,
    "minimizeOutputTokens": True,
})
config.setdefault("autoLoad", ["CLAUDE.md", "AGENTS.md"])

path.write_text(json.dumps(config, indent=2) + "\n")
PYEOF
  log_info "omp settings written to $OMP_SETTINGS"

  # Write managed-by marker
  if [[ -f "$OMP_CFG_DIR/.managed-by" ]]; then
    local _eb
    _eb=$(cat "$OMP_CFG_DIR/.managed-by" 2>/dev/null || echo "")
    [[ "$_eb" == "pi" ]] && echo "both" > "$OMP_CFG_DIR/.managed-by"
  else
    echo "omp" > "$OMP_CFG_DIR/.managed-by"
  fi
}

# ---- Phase 6: Unified MCP configuration ------------------------------
configure_unified_mcp() {
  if [[ "${PRESET_ACTIVE:-false}" == "true" ]] && [[ -n "${PRESET_MCP_SCENARIOS:-}" ]]; then
    SCENARIOS="$PRESET_MCP_SCENARIOS"
    log_info "Using preset MCP scenarios: $SCENARIOS"
  else
    SCENARIOS=$(mcp_select_scenarios "MCP Toolkits (all agents)")
  fi

  if [[ -z "$SCENARIOS" ]]; then
    log_info "No MCP scenarios selected — skipping MCP config"
    return 0
  fi

  CREDS=$(mcp_collect_credentials "$SCENARIOS")
  IFS='|' read -r _srv _brave _github _pg _sqlite <<< "$CREDS"

  # Write MCP configs to each selected agent
  if [[ -n "${AGENT_SELECTED[claude-code]:-}" ]]; then
    mcp_write_json "$HOME/.claude/settings.json" "mcpServers" "$SCENARIOS" "$CREDS"
    log_info "Claude Code MCP servers written"
  fi

  if [[ -n "${AGENT_SELECTED[codex]:-}" ]]; then
    mcp_write_toml "$HOME/.codex/config.toml" "$SCENARIOS" "$CREDS"
    log_info "Codex MCP servers written"
  fi

  if [[ -n "${AGENT_SELECTED[opencode]:-}" ]]; then
    mcp_write_json_local "$HOME/.config/opencode/opencode.json" "mcp" "$SCENARIOS" "$CREDS"
    log_info "opencode MCP servers written"
  fi

  if [[ -n "${AGENT_SELECTED[pi]:-}" ]]; then
    mcp_write_json "$HOME/.pi/agent/settings.json" "mcpServers" "$SCENARIOS" "$CREDS"
    log_info "Pi MCP servers written"
  fi

  # omp shares the same settings.json as pi, so its MCP is already written
  if [[ -n "${AGENT_SELECTED[omp]:-}" ]]; then
    log_info "omp MCP servers (shared with pi config)"
  fi
}

# ---- Phase 7: Shell Functions + Summary ------------------------------
install_shell_helpers() {
  FISH_FUNC_DIR="$HOME/.config/fish/functions"
  mkdir -p "$FISH_FUNC_DIR"

  # pi-env
  if [[ -n "${AGENT_SELECTED[pi]:-}" ]]; then
    cat > "${FISH_FUNC_DIR}/pi_env.fish" << 'FEOF'
function pi_env
    set -l key_file ~/.config/rinbarpen/api-keys.env
    if test -f $key_file
        bass source $key_file
        echo "pi environment loaded"
    else
        echo "No api-keys.env found"
        return 1
    end
end
FEOF
    if ! grep -q "# pi-env (added by setup)" "$HOME/.bashrc" 2>/dev/null; then
      cat >> "$HOME/.bashrc" << 'BASHEOF'

# pi-env (added by setup)
pi-env() { source ~/.config/rinbarpen/api-keys.env 2>/dev/null && echo "pi env loaded" || echo "No api-keys.env"; }
BASHEOF
    fi
  fi

  # omp-env
  if [[ -n "${AGENT_SELECTED[omp]:-}" ]]; then
    cat > "${FISH_FUNC_DIR}/omp_env.fish" << 'FEOF'
function omp_env
    set -l key_file ~/.config/rinbarpen/api-keys.env
    if test -f $key_file
        bass source $key_file
        echo "omp environment loaded"
    else
        echo "No api-keys.env found"
        return 1
    end
end
FEOF
    if ! grep -q "# omp-env (added by setup)" "$HOME/.bashrc" 2>/dev/null; then
      cat >> "$HOME/.bashrc" << 'BASHEOF'

# omp-env (added by setup)
omp-env() { source ~/.config/rinbarpen/api-keys.env 2>/dev/null && echo "omp env loaded" || echo "No api-keys.env"; }
BASHEOF
    fi
  fi

  log_info "Shell helper functions installed"
}

print_summary() {
  echo ""
  log_info "===== Agent Configuration Summary ====="
  for agent in "opencode" "codex" "claude-code" "pi" "omp"; do
    if [[ -n "${AGENT_SELECTED[$agent]:-}" ]]; then
      printf "  %-16s %s\n" "$agent" "✓ configured"
    else
      printf "  %-16s %s\n" "$agent" "— skipped"
    fi
  done
  echo ""
  log_info "Cache optimizations applied:"
  echo "  - Non-essential traffic disabled"
  echo "  - Max output tokens: 1,000,000"
  echo "  - Consistent system prompts (CLAUDE.md/AGENTS.md)"
  echo "  - Hash-anchored edits (omp)"
  echo ""
  log_info "Config files:"
  [[ -n "${AGENT_SELECTED[claude-code]:-}" ]] && echo "  ~/.claude/settings.json"
  [[ -n "${AGENT_SELECTED[codex]:-}" ]]      && echo "  ~/.codex/config.toml"
  [[ -n "${AGENT_SELECTED[opencode]:-}" ]]    && echo "  ~/.config/opencode/opencode.json"
  [[ -n "${AGENT_SELECTED[pi]:-}" ]]          && echo "  ~/.pi/agent/settings.json"
  [[ -n "${AGENT_SELECTED[omp]:-}" ]]         && echo "  ~/.pi/agent/settings.json (shared with pi)"
}

# ---- Phase 8: Save as Preset ----------------------------------------
save_as_preset() {
  # Skip in non-interactive/test environments
  [[ -n "${SKIP_PRESET_SAVE:-}" ]] && return 0

  if [[ "${PRESET_ACTIVE:-false}" == "true" ]]; then
    log_info "Current config was loaded from a preset — skipping save"
    return 0
  fi

  if ! command -v whiptail &>/dev/null; then
    return 0  # Non-interactive, don't try to save
  fi

  if ! whiptail --yesno "Save current settings as a new preset?" 8 50; then
    return 0
  fi

  local preset_name
  preset_name=$(whiptail --title "Save Preset" --inputbox "Preset name:" 8 50 "my-config" 3>&1 1>&2 2>&3) || return 0
  [[ -z "$preset_name" ]] && return 0

  local preset_file="$PRESET_DIR/${preset_name}.json"

  python3 - "$preset_file" << PYEOF
import json, os, pathlib, sys

preset = {
    "name": "${preset_name}",
    "displayName": "${preset_name}",
    "description": "User-created preset",
    "version": 1,
    "provider": {"defaultProvider": os.environ.get("SHARED_PROVIDER", "deepseek")},
    "agents": {
        "claude-code": {
            "enabled": ${AGENT_SELECTED[claude-code]+true}${AGENT_SELECTED[claude-code]-false},
            "model": os.environ.get("CLAUDE_MODEL", "deepseek-v4-flash"),
            "planModel": os.environ.get("CLAUDE_PLAN_MODEL", "deepseek-v4-pro"),
            "permissionMode": os.environ.get("PERM_MODE", "acceptEdits"),
        },
        "codex": {
            "enabled": ${AGENT_SELECTED[codex]+true}${AGENT_SELECTED[codex]-false},
            "model": os.environ.get("CODEX_MODEL", "deepseek-v4-pro"),
            "planModel": os.environ.get("CODEX_PLAN_MODEL", "deepseek-v4-pro"),
            "reasoningEffort": os.environ.get("CODEX_REASONING", "medium"),
            "planReasoningEffort": os.environ.get("CODEX_PLAN_REASONING", "xhigh"),
            "approvalPolicy": os.environ.get("CODEX_APPROVAL", "on-request"),
        },
        "opencode": {
            "enabled": ${AGENT_SELECTED[opencode]+true}${AGENT_SELECTED[opencode]-false},
            "model": os.environ.get("DEFAULT_MODEL", "deepseek/deepseek-v4-flash"),
            "planModel": os.environ.get("PLAN_MODEL", "openai/gpt-5.5"),
            "reasoningEffort": "xhigh",
        },
        "pi": {
            "enabled": ${AGENT_SELECTED[pi]+true}${AGENT_SELECTED[pi]-false},
            "model": os.environ.get("PI_MODEL", "deepseek-v4-flash"),
            "provider": os.environ.get("PI_PROVIDER", "deepseek"),
            "maxTokens": 1000000,
            "cache": {"consistentPrompt": True},
        },
        "omp": {
            "enabled": ${AGENT_SELECTED[omp]+true}${AGENT_SELECTED[omp]-false},
            "model": os.environ.get("OMP_MODEL", "deepseek-v4-pro"),
            "provider": os.environ.get("OMP_PROVIDER", "deepseek"),
            "features": {
                "hashAnchoredEdits": os.environ.get("OMP_HASH_EDITS", "true") == "true",
                "snapcompact": os.environ.get("OMP_SNAPCOMPACT", "true") == "true",
                "lsp": os.environ.get("OMP_LSP", "false") == "true",
                "dap": os.environ.get("OMP_DAP", "false") == "true",
            },
        },
    },
    "mcp": {"scenarios": []},
}

path = pathlib.Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(preset, indent=2) + "\n")
print(f"Preset saved to {path}")
PYEOF

  log_info "Preset saved: $preset_file"
}

# ---- Main Execution --------------------------------------------------
main() {
  log_info "=== Unified Agent Configuration ==="

  select_agents

  local agent_count=0
  for _a in "${!AGENT_SELECTED[@]}"; do agent_count=$((agent_count + 1)); done
  if [[ "$agent_count" -eq 0 ]]; then
    log_warn "No agents selected — exiting"
    exit 0
  fi

  detect_and_load_preset
  collect_shared_config

  # Phase 4: Per-agent configuration
  [[ -n "${AGENT_SELECTED[claude-code]:-}" ]] && configure_claude_code
  [[ -n "${AGENT_SELECTED[codex]:-}" ]]      && configure_codex
  [[ -n "${AGENT_SELECTED[opencode]:-}" ]]    && configure_opencode
  [[ -n "${AGENT_SELECTED[pi]:-}" ]]          && configure_pi
  [[ -n "${AGENT_SELECTED[omp]:-}" ]]         && configure_omp

  # Phase 5/6: Unified MCP
  configure_unified_mcp

  # Phase 7: Shell helpers + summary
  install_shell_helpers
  print_summary

  # Phase 8: Save as preset
  save_as_preset

  log_info "all-agents: done"
}

main "$@"
