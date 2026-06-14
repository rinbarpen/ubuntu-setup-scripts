#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"
source "${SCRIPT_DIR}/../lib/api.sh"

need_cmd npm
need_cmd python3

CODEX_CFG="$HOME/.codex/config.toml"
CODEX_LEGACY_CFG="$HOME/.codex/config.yaml"

# Install codex CLI (skip if already installed)
if command -v codex &>/dev/null; then
  log_info "codex CLI already installed ($(command -v codex)), skipping npm install"
else
  log_info "Installing codex CLI..."
  npm install -g @openai/codex
fi

if [[ -f "$CODEX_LEGACY_CFG" ]]; then
  log_warn "Found legacy Codex config at $CODEX_LEGACY_CFG; current Codex CLI uses $CODEX_CFG. Leaving legacy file unchanged."
fi

mkdir -p "$(dirname "$CODEX_CFG")"

# =============================================
# 1. Model Provider Profiles
# =============================================

# Detect existing providers from config
CODEX_PROVIDERS_JSON="{}"
if [[ -f "$CODEX_CFG" ]]; then
  CODEX_PROVIDERS_JSON=$(python3 -c "
import tomllib, pathlib, json
try:
    c = tomllib.loads(pathlib.Path('$CODEX_CFG').read_text())
    provs = c.get('model_providers', {})
    result = {}
    for k, v in provs.items():
        result[k] = {sk: sv for sk, sv in v.items() if isinstance(sv, (str, int, float, bool))}
    print(json.dumps(result))
except: print(json.dumps({}))
" 2>/dev/null || echo '{}')
fi
export CODEX_PROVIDERS_JSON

# Show existing providers
_existing_count=$(echo "$CODEX_PROVIDERS_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
if [[ "$_existing_count" -gt 0 ]]; then
  log_info "Existing providers:"
  echo "$CODEX_PROVIDERS_JSON" | python3 -c "
import sys, json
for k, v in json.load(sys.stdin).items():
    print(f'  - {k}: {v.get(\"name\", k)} ({v.get(\"base_url\", \"?\")})')
"
fi

if command -v whiptail &>/dev/null; then
  for _prov_idx in 1 2 3 4 5; do
    _do_add=$(whiptail --title "Codex Provider" --menu "Add a model provider?" 10 50 2 \
      "yes" "添加供应商" \
      "no"  "完成" \
      3>&1 1>&2 2>&3) || _do_add="no"
    [[ "$_do_add" != "yes" ]] && break

    PROVIDER_TYPE=$(whiptail --title "Provider Type" --menu "Select provider type:" 22 65 10 \
      "openai"     "OpenAI (https://api.openai.com/v1)" \
      "deepseek"   "DeepSeek (https://api.deepseek.com)" \
      "openrouter" "OpenRouter relay (GPT, Claude via relay)" \
      "aihubmix"   "AIHubMix relay (GPT, Claude via relay)" \
      "azure"      "Azure OpenAI" \
      "ollama"     "Ollama (local)" \
      "lmstudio"   "LM Studio (local)" \
      "custom"     "自定义供应商" \
      3>&1 1>&2 2>&3) || break

    _name=""
    _display=""
    _base_url=""
    _env_key=""
    _wire_api="chat"

    case "$PROVIDER_TYPE" in
      openai)
        _name="openai"; _display="OpenAI"
        _base_url="https://api.openai.com/v1"
        _env_key="OPENAI_API_KEY"; _wire_api="responses" ;;
      deepseek)
        _name="deepseek"; _display="DeepSeek"
        _base_url="https://api.deepseek.com"
        _env_key="DEEPSEEK_API_KEY"; _wire_api="chat" ;;
      openrouter)
        _name="openrouter"; _display="OpenRouter"
        _base_url="https://openrouter.ai/api/v1"
        _env_key="OPENROUTER_API_KEY"; _wire_api="chat" ;;
      aihubmix)
        _name="aihubmix"; _display="AIHubMix"
        _base_url="https://aihubmix.com/v1"
        _env_key="AIHUBMIX_API_KEY"; _wire_api="chat" ;;
      azure)
        _name="azure"; _display="Azure OpenAI"
        _base_url=$(whiptail --inputbox "Azure endpoint URL:" 8 60 --title "Azure" 3>&1 1>&2 2>&3) || break
        _env_key="AZURE_OPENAI_API_KEY"; _wire_api="responses" ;;
      ollama)
        _name="ollama"; _display="Ollama"
        _base_url=$(whiptail --inputbox "Ollama base URL [http://localhost:11434/v1]:" 8 60 "http://localhost:11434/v1" --title "Ollama" 3>&1 1>&2 2>&3) || break
        _env_key=""; _wire_api="chat" ;;
      lmstudio)
        _name="lmstudio"; _display="LM Studio"
        _base_url=$(whiptail --inputbox "LM Studio base URL [http://localhost:1234/v1]:" 8 60 "http://localhost:1234/v1" --title "LM Studio" 3>&1 1>&2 2>&3) || break
        _env_key=""; _wire_api="chat" ;;
      custom)
        _name=$(whiptail --inputbox "Provider ID (e.g. myproxy):" 8 60 --title "Custom" 3>&1 1>&2 2>&3) || break
        [[ -z "$_name" ]] && { log_warn "Provider ID cannot be empty"; continue; }
        _display=$(whiptail --inputbox "Display name [$_name]:" 8 60 "$_name" --title "Custom" 3>&1 1>&2 2>&3) || break
        _base_url=$(whiptail --inputbox "Base URL:" 8 60 --title "Custom" 3>&1 1>&2 2>&3) || break
        _env_key=$(whiptail --inputbox "API key env var (leave empty if not needed):" 8 60 --title "Custom" 3>&1 1>&2 2>&3) || break
        _wire_api=$(whiptail --menu "API format:" 10 40 2 \
          "chat"      "Chat Completions API" \
          "responses" "OpenAI Responses API" \
          3>&1 1>&2 2>&3) || _wire_api="chat" ;;
    esac

    # Build/update providers JSON
    CODEX_PROVIDERS_JSON=$(python3 -c "
import json, os
d = json.loads(os.environ.get('CODEX_PROVIDERS_JSON', '{}'))
d['$_name'] = {'name': '$_display', 'base_url': '$_base_url', 'wire_api': '$_wire_api'}
if '$_env_key':
    d['$_name']['env_key'] = '$_env_key'
print(json.dumps(d))
")
    export CODEX_PROVIDERS_JSON

    # Prompt for API key
    if [[ -n "$_env_key" ]]; then
      api_key_get "$_env_key" "${_env_key} (for ${_display})" true
    fi
    log_info "Added provider: $_display"
  done
fi

# =============================================
# 2. Default Provider & Model Selection
# =============================================

CODEX_DEFAULT_PROVIDER=""
CODEX_MODEL=""
_existing_model=""

if [[ -f "$CODEX_CFG" ]]; then
  _existing_model=$(python3 -c "
import tomllib, pathlib
try:
    c = tomllib.loads(pathlib.Path('$CODEX_CFG').read_text())
    print(c.get('model',''))
except: pass
" 2>/dev/null || echo "")
fi

# Build provider ID list from JSON
_provider_ids=$(echo "$CODEX_PROVIDERS_JSON" | python3 -c "
import sys, json
for k in json.load(sys.stdin): print(k)
" 2>/dev/null || true)

if [[ -n "$_provider_ids" ]] && command -v whiptail &>/dev/null; then
  _menu_items=()
  while IFS= read -r pid; do
    _display_name=$(echo "$CODEX_PROVIDERS_JSON" | python3 -c "
import sys, json
print(json.load(sys.stdin).get('$pid', {}).get('name', '$pid'))
")
    _menu_items+=("$pid" "$_display_name")
  done <<< "$_provider_ids"

  _provider_count=$(echo "$_provider_ids" | wc -l)
  _provider_choice=$(whiptail --title "Default Provider" --menu \
    "Select default provider:" \
    $((_provider_count * 2 + 7)) 50 "$_provider_count" \
    "${_menu_items[@]}" \
    3>&1 1>&2 2>&3) || _provider_choice=""

  if [[ -n "$_provider_choice" ]]; then
    CODEX_DEFAULT_PROVIDER="$_provider_choice"
    export CODEX_DEFAULT_PROVIDER

    _current_model_hint="$_existing_model"
    [[ -z "$_current_model_hint" ]] && _current_model_hint="gpt-5"
    CODEX_MODEL=$(whiptail --inputbox \
      "Model ID for ${_provider_choice} (e.g. gpt-5, deepseek-v4-pro):" \
      8 60 "$_current_model_hint" --title "Model" 3>&1 1>&2 2>&3) || CODEX_MODEL=""

    if [[ -n "$CODEX_MODEL" ]]; then
      # Prompt for API key if this provider uses one
      _env_key=$(echo "$CODEX_PROVIDERS_JSON" | python3 -c "
import sys, json
print(json.load(sys.stdin).get('$_provider_choice', {}).get('env_key', ''))
")
      if [[ -n "$_env_key" ]]; then
        api_key_get "$_env_key" "${_env_key} (for ${_provider_choice})" true
      fi
    fi
    export CODEX_MODEL
  fi
fi

# =============================================
# 3. Plan Mode Model
# =============================================

CODEX_PLAN_MODEL="deepseek-v4-pro"
if [[ -f "$CODEX_CFG" ]]; then
  _existing_plan_model=$(python3 -c "
import tomllib, pathlib
try:
    c = tomllib.loads(pathlib.Path('$CODEX_CFG').read_text())
    print(c.get('plan_model',''))
except: pass
" 2>/dev/null || echo "")
  [[ -n "$_existing_plan_model" ]] && CODEX_PLAN_MODEL="$_existing_plan_model"
fi

if command -v whiptail &>/dev/null; then
  _plan_info="当前: ${CODEX_PLAN_MODEL}"
  PLAN_CHOICE=$(whiptail --title "Codex Plan Model" --menu "Select model for Plan mode (deep reasoning):\n${_plan_info}" 22 75 12 \
      "deepseek-v4-pro"  "DeepSeek V4 Pro (推荐)" \
      "deepseek-v4-flash" "DeepSeek V4 Flash (快但稍弱)" \
      "gpt-5.5"          "GPT-5.5 (via OpenAI/relay)" \
      "gpt-4o"           "GPT-4o (via OpenAI/relay)" \
      "claude-sonnet-4-20250514" "Claude Sonnet 4 (via relay)" \
      "custom"           "Custom model ID" \
      "do-not-set"       "Do not set plan model" \
      3>&1 1>&2 2>&3) || PLAN_CHOICE=""

  case "$PLAN_CHOICE" in
    deepseek-v4-pro|deepseek-v4-flash) CODEX_PLAN_MODEL="$PLAN_CHOICE" ;;
    custom) read -r -p "Enter plan model ID: " CODEX_PLAN_MODEL ;;
    do-not-set) CODEX_PLAN_MODEL="" ;;
    *) ;;  # keep existing default
  esac
fi
export CODEX_PLAN_MODEL

# =============================================
# 4. Features Configuration
# =============================================

CODEX_FEATURES_CONFIGURED="false"
CODEX_FEATURES_MEMORIES="false"
CODEX_FEATURES_HOOKS="true"
CODEX_FEATURES_UNDO="false"
CODEX_FEATURES_APPS="false"
CODEX_FEATURES_NETWORK_PROXY="false"

# Read existing features from config
if [[ -f "$CODEX_CFG" ]]; then
  _existing_features=$(python3 -c "
import tomllib, pathlib, json
try:
    c = tomllib.loads(pathlib.Path('$CODEX_CFG').read_text())
    f = c.get('features', {})
    print(json.dumps({k: v for k, v in f.items() if isinstance(v, bool)}))
except: print('{}')
" 2>/dev/null || echo '{}')

  for _fk in memories hooks undo apps network_proxy; do
    _fv=$(echo "$_existing_features" | python3 -c "
import sys, json
v = json.load(sys.stdin).get('$_fk')
print(str(v).lower() if v is not None else '')
" 2>/dev/null || echo "")
    if [[ "$_fv" == "true" ]]; then
      varname="CODEX_FEATURES_$(echo "$_fk" | tr '[:lower:]' '[:upper:]')"
      printf -v "$varname" "true"
    elif [[ "$_fv" == "false" ]]; then
      varname="CODEX_FEATURES_$(echo "$_fk" | tr '[:lower:]' '[:upper:]')"
      printf -v "$varname" "false"
    fi
  done
fi

if command -v whiptail &>/dev/null; then
  _mem_status="OFF"; [[ "${CODEX_FEATURES_MEMORIES}" == "true" ]] && _mem_status="ON"
  _hooks_status="OFF"; [[ "${CODEX_FEATURES_HOOKS}" == "true" ]] && _hooks_status="ON"
  _undo_status="OFF"; [[ "${CODEX_FEATURES_UNDO}" == "true" ]] && _undo_status="ON"
  _apps_status="OFF"; [[ "${CODEX_FEATURES_APPS}" == "true" ]] && _apps_status="ON"
  _net_status="OFF"; [[ "${CODEX_FEATURES_NETWORK_PROXY}" == "true" ]] && _net_status="ON"

  FEATURE_CHOICES=$(whiptail --title "Codex Features" --checklist \
    "Toggle features (SPACE to toggle, TAB to finish):" 18 65 6 \
    "memories"      "记忆系统 (Memories)"              "$_mem_status" \
    "hooks"         "生命周期钩子 (lifecycle hooks)"    "$_hooks_status" \
    "undo"          "撤销支持 (undo via git snapshots)" "$_undo_status" \
    "apps"          "ChatGPT Apps 支持 (实验性)"        "$_apps_status" \
    "network_proxy" "沙箱网络代理 (实验性)"             "$_net_status" \
    3>&1 1>&2 2>&3) || FEATURE_CHOICES=""

  # Reset and apply choices
  CODEX_FEATURES_MEMORIES="false"; CODEX_FEATURES_HOOKS="false"
  CODEX_FEATURES_UNDO="false"; CODEX_FEATURES_APPS="false"
  CODEX_FEATURES_NETWORK_PROXY="false"
  for _f in $FEATURE_CHOICES; do
    _f=$(echo "$_f" | tr -d '"')
    case "$_f" in
      memories)      CODEX_FEATURES_MEMORIES="true" ;;
      hooks)         CODEX_FEATURES_HOOKS="true" ;;
      undo)          CODEX_FEATURES_UNDO="true" ;;
      apps)          CODEX_FEATURES_APPS="true" ;;
      network_proxy) CODEX_FEATURES_NETWORK_PROXY="true" ;;
    esac
  done
  CODEX_FEATURES_CONFIGURED="true"
fi

export CODEX_FEATURES_CONFIGURED CODEX_FEATURES_MEMORIES CODEX_FEATURES_HOOKS \
  CODEX_FEATURES_UNDO CODEX_FEATURES_APPS CODEX_FEATURES_NETWORK_PROXY

# =============================================
# 5. TUI Configuration
# =============================================

CODEX_TUI_CONFIGURED="false"
CODEX_TUI_ANIMATIONS="true"
CODEX_TUI_ALT_SCREEN="never"
CODEX_TUI_TOOLTIPS="false"

# Read existing TUI settings
if [[ -f "$CODEX_CFG" ]]; then
  _existing_tui=$(python3 -c "
import tomllib, pathlib, json
try:
    c = tomllib.loads(pathlib.Path('$CODEX_CFG').read_text())
    t = c.get('tui', {})
    print(json.dumps(t))
except: print('{}')
" 2>/dev/null || echo '{}')

  _ta=$(echo "$_existing_tui" | python3 -c "
import sys, json; v = json.load(sys.stdin).get('animations')
print(str(v).lower() if v is not None else 'true')
" 2>/dev/null)
  [[ "$_ta" == "false" ]] && CODEX_TUI_ANIMATIONS="false"

  _tas=$(echo "$_existing_tui" | python3 -c "
import sys, json; print(json.load(sys.stdin).get('alternate_screen','never'))
" 2>/dev/null)
  [[ -n "$_tas" ]] && CODEX_TUI_ALT_SCREEN="$_tas"

  _tt=$(echo "$_existing_tui" | python3 -c "
import sys, json; v = json.load(sys.stdin).get('show_tooltips')
print(str(v).lower() if v is not None else 'false')
" 2>/dev/null)
  [[ "$_tt" == "true" ]] && CODEX_TUI_TOOLTIPS="true"
fi

if command -v whiptail &>/dev/null; then
  _anim_status="OFF"; [[ "${CODEX_TUI_ANIMATIONS}" == "true" ]] && _anim_status="ON"
  _tooltip_status="OFF"; [[ "${CODEX_TUI_TOOLTIPS}" == "true" ]] && _tooltip_status="ON"

  TUI_CHOICES=$(whiptail --title "Codex TUI Settings" --checklist \
    "TUI options (SPACE to toggle, TAB to finish):" 14 60 3 \
    "animations" "ASCII 动画" "$_anim_status" \
    "tooltips"   "新手引导 tooltips" "$_tooltip_status" \
    3>&1 1>&2 2>&3) || TUI_CHOICES=""

  CODEX_TUI_ANIMATIONS="false"
  CODEX_TUI_TOOLTIPS="false"
  for _t in $TUI_CHOICES; do
    _t=$(echo "$_t" | tr -d '"')
    case "$_t" in
      animations) CODEX_TUI_ANIMATIONS="true" ;;
      tooltips)   CODEX_TUI_TOOLTIPS="true" ;;
    esac
  done

  _alt_choice=$(whiptail --title "Alternate Screen" --menu \
    "Alternate screen mode:" 12 50 3 \
    "never" "保留终端回滚 (推荐)" \
    "auto"  "自动管理" \
    3>&1 1>&2 2>&3) || _alt_choice="never"
  CODEX_TUI_ALT_SCREEN="$_alt_choice"

  CODEX_TUI_CONFIGURED="true"
fi

export CODEX_TUI_CONFIGURED CODEX_TUI_ANIMATIONS CODEX_TUI_ALT_SCREEN CODEX_TUI_TOOLTIPS

# =============================================
# 6. Approval Policy
# =============================================

CODEX_APPROVAL="on-request"
if [[ -f "$CODEX_CFG" ]]; then
  _existing_approval=$(python3 -c "
import tomllib, pathlib
try:
    c = tomllib.loads(pathlib.Path('$CODEX_CFG').read_text())
    print(c.get('approval_policy',''))
except: pass
" 2>/dev/null || echo "")
  [[ -n "$_existing_approval" ]] && CODEX_APPROVAL="$_existing_approval"
fi

if command -v whiptail &>/dev/null; then
  _approval_info="当前: ${CODEX_APPROVAL}"
  APPROVAL_CHOICE=$(whiptail --title "Codex Approval Policy" --menu "Select default approval policy:\n${_approval_info}" 18 70 4 \
    "on-request"  "按需批准 (On request)" \
    "never"       "从不询问 (Never ask — bypass equivalent)" \
    "always"      "始终询问 (Always ask)" \
    3>&1 1>&2 2>&3) || APPROVAL_CHOICE=""

  case "$APPROVAL_CHOICE" in
    on-request|never|always) CODEX_APPROVAL="$APPROVAL_CHOICE" ;;
    *) ;;  # keep existing default
  esac
fi
export CODEX_APPROVAL

# =============================================
# 7. Write Config (Python)
# =============================================

python3 - "$CODEX_CFG" << 'PYEOF'
import json
import os
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])

approval_policy = os.environ.get("CODEX_APPROVAL", "on-request")

managed = {
    "model_reasoning_effort": "medium",
    "plan_mode_reasoning_effort": "xhigh",
    "approval_policy": approval_policy,
    "sandbox_mode": "workspace-write",
}

codex_model = os.environ.get("CODEX_MODEL", "")
if codex_model:
    managed["model"] = codex_model

codex_plan_model = os.environ.get("CODEX_PLAN_MODEL", "")
if codex_plan_model:
    managed["plan_model"] = codex_plan_model

default_provider = os.environ.get("CODEX_DEFAULT_PROVIDER", "")
if default_provider:
    managed["model_provider"] = default_provider

# Deprecated keys to remove from config (migrated to model_providers)
deprecated = {"openai_base_url", "openai_api_key"}
skip_keys = set(managed.keys()) | deprecated

# Managed table prefixes (these whole sections get removed and rewritten)
managed_tables = {"features", "tui", "model_providers"}

lines = path.read_text().splitlines(True) if path.exists() else []
key_re = re.compile(r"^\s*([A-Za-z0-9_-]+)\s*=")
table_re = re.compile(r"^\s*\[([^\]]+)\]\s*$")

top, rest = [], []
in_tables = False
for line in lines:
    if table_re.match(line):
        in_tables = True
    if in_tables:
        rest.append(line)
        continue
    match = key_re.match(line)
    if match and (match.group(1) in skip_keys):
        continue
    top.append(line)

# Remove managed table sections from rest
rest_out = []
skip = False
for line in rest:
    match = table_re.match(line)
    if match:
        table_name = match.group(1)
        skip = any(
            table_name == mt or table_name.split(".")[0] == mt
            for mt in managed_tables
        )
    if not skip:
        rest_out.append(line)

# Clean trailing whitespace from top
while top and not top[-1].strip():
    top.pop()

# Build output
out = top[:]
if out:
    out.append("\n")

# Write managed top-level keys (sorted for readability)
for key in sorted(managed.keys()):
    out.append(f"{key} = {json.dumps(managed[key])}\n")

# --- Features section ---
features_configured = os.environ.get("CODEX_FEATURES_CONFIGURED") == "true"
if features_configured:
    if out and out[-1].strip():
        out.append("\n")
    out.append("[features]\n")
    for feat in ["memories", "hooks", "undo", "apps", "network_proxy"]:
        env_key = f"CODEX_FEATURES_{feat.upper()}"
        val = os.environ.get(env_key, "false")
        out.append(f"{feat} = {'true' if val == 'true' else 'false'}\n")

# --- TUI section ---
tui_configured = os.environ.get("CODEX_TUI_CONFIGURED") == "true"
if tui_configured:
    if out and out[-1].strip():
        out.append("\n")
    out.append("[tui]\n")
    anim = os.environ.get("CODEX_TUI_ANIMATIONS", "true")
    out.append(f"animations = {'true' if anim == 'true' else 'false'}\n")
    alt_screen = os.environ.get("CODEX_TUI_ALT_SCREEN", "never")
    out.append(f"alternate_screen = {json.dumps(alt_screen)}\n")
    tooltips = os.environ.get("CODEX_TUI_TOOLTIPS", "false")
    out.append(f"show_tooltips = {'true' if tooltips == 'true' else 'false'}\n")

# --- Model Providers section ---
providers_json = os.environ.get("CODEX_PROVIDERS_JSON", "{}")
try:
    providers_data = json.loads(providers_json)
except json.JSONDecodeError:
    providers_data = {}

if providers_data:
    for prov_id in sorted(providers_data.keys()):
        prov_config = providers_data[prov_id]
        if out and out[-1].strip():
            out.append("\n")
        out.append(f"[model_providers.{prov_id}]\n")
        for key in ["name", "base_url", "env_key", "wire_api"]:
            if key in prov_config:
                value = prov_config[key]
                if isinstance(value, bool):
                    out.append(f"{key} = {'true' if value else 'false'}\n")
                else:
                    out.append(f"{key} = {json.dumps(value)}\n")

# Append remaining non-managed tables
if rest_out:
    if out and out[-1].strip():
        out.append("\n")
    out.extend(rest_out)

path.write_text("".join(out))
PYEOF
log_info "Codex defaults written to $CODEX_CFG"

# =============================================
# 8. MCP Toolkits (existing)
# =============================================

# codex-auth function
FISH_FUNC_DIR="$HOME/.config/fish/functions"
mkdir -p "$FISH_FUNC_DIR"

cat > "${FISH_FUNC_DIR}/codex_auth.fish" << 'EOF'
function codex_auth
    set -l cfg "$HOME/.codex/config.toml"
    set -l provider "openai"
    if test -f "$cfg"
        set provider (grep -m1 '^model_provider' "$cfg" | sed 's/.*= *"\(.*\)"/\1/' 2>/dev/null; or echo "openai")
    end

    switch "$provider"
        case "openrouter"
            read -s -P "Enter OPENROUTER_API_KEY: " key
            set -gx OPENROUTER_API_KEY $key
            echo "OPENROUTER_API_KEY set for this session"
        case "aihubmix"
            read -s -P "Enter AIHUBMIX_API_KEY: " key
            set -gx AIHUBMIX_API_KEY $key
            echo "AIHUBMIX_API_KEY set for this session"
        case "deepseek"
            read -s -P "Enter DEEPSEEK_API_KEY: " key
            set -gx DEEPSEEK_API_KEY $key
            echo "DEEPSEEK_API_KEY set for this session"
        case '*'
            read -s -P "Enter OPENAI_API_KEY: " key
            set -gx OPENAI_API_KEY $key
            echo "OPENAI_API_KEY set for this session"
    end
end
EOF

if ! grep -q "# codex-auth (added by setup)" "$HOME/.bashrc" 2>/dev/null; then
cat >> "$HOME/.bashrc" << 'BASHEOF'

# codex-auth (added by setup)
codex-auth() {
  local cfg="$HOME/.codex/config.toml"
  local provider="openai"
  if [[ -f "$cfg" ]]; then
    provider=$(grep -m1 '^model_provider' "$cfg" | sed 's/.*= *"\(.*\)"/\1/' 2>/dev/null || echo "openai")
  fi
  case "$provider" in
    openrouter)
      read -r -s -p "Enter OPENROUTER_API_KEY: " key; echo ""
      export OPENROUTER_API_KEY="$key"
      echo "OPENROUTER_API_KEY set for this session" ;;
    aihubmix)
      read -r -s -p "Enter AIHUBMIX_API_KEY: " key; echo ""
      export AIHUBMIX_API_KEY="$key"
      echo "AIHUBMIX_API_KEY set for this session" ;;
    deepseek)
      read -r -s -p "Enter DEEPSEEK_API_KEY: " key; echo ""
      export DEEPSEEK_API_KEY="$key"
      echo "DEEPSEEK_API_KEY set for this session" ;;
    *)
      read -r -s -p "Enter OPENAI_API_KEY: " key; echo ""
      export OPENAI_API_KEY="$key"
      echo "OPENAI_API_KEY set for this session" ;;
  esac
}
BASHEOF
fi

# Show existing MCP servers if any
if [[ -f "$CODEX_CFG" ]]; then
  _existing_mcp=$(python3 -c "
import tomllib, pathlib
try:
    c = tomllib.loads(pathlib.Path('$CODEX_CFG').read_text())
    mcps = c.get('mcp_servers', {})
    if mcps:
        for k in mcps: print(f'  - {k}')
except: pass
" 2>/dev/null)
  if [[ -n "$_existing_mcp" ]]; then
    log_info "Currently configured MCP servers:"
    echo "$_existing_mcp"
  fi
fi

if command -v whiptail &>/dev/null; then
  SCENARIO_CHOICES=$(whiptail --title "MCP Toolkits (codex)" --checklist \
      "Select toolkits to configure for codex (SPACE to toggle):" 20 65 11 \
      "recommended" "推荐: context7, brave-search, excalidraw, puppeteer" ON  \
      "frontend"   "前端开发: context7, excalidraw, puppeteer"   OFF \
      "backend"    "后端开发: context7, github, postgres, sqlite" OFF \
      "testing"    "测试:     context7, github, puppeteer"       OFF \
      "research"   "科研/ARIS: brave-search, puppeteer, context7, sqlite" ON  \
      "auto-research-in-sleeping" "ARIS 自动研究: brave-search, puppeteer, context7, sqlite" OFF \
      "analyst"    "分析师:   brave-search, context7, postgres"  OFF \
      "stock"      "股票:     brave-search, context7"            OFF \
      "marketing"  "市场:     brave-search, excalidraw"          OFF \
      "daily"      "日常:     brave-search, context7"            ON  \
      "chat"       "对话:     brave-search, context7"            ON  \
      3>&1 1>&2 2>&3) || SCENARIO_CHOICES=""
  SCENARIOS=$(echo "$SCENARIO_CHOICES" | tr -d '"')
else
  log_warn "whiptail not found — skipping MCP toolkit selection for codex"
  SCENARIOS=""
fi

if [[ -n "$SCENARIOS" ]]; then
  declare -A NEED_MCP
  for scenario in $SCENARIOS; do
    case "$scenario" in
      recommended) NEED_MCP[context7]=1; NEED_MCP[brave-search]=1; NEED_MCP[excalidraw]=1; NEED_MCP[puppeteer]=1 ;;
      frontend)  NEED_MCP[context7]=1; NEED_MCP[excalidraw]=1; NEED_MCP[puppeteer]=1; NEED_MCP[dev-chrome]=1 ;;
      backend)   NEED_MCP[context7]=1; NEED_MCP[github]=1; NEED_MCP[postgres]=1; NEED_MCP[sqlite]=1 ;;
      testing)   NEED_MCP[context7]=1; NEED_MCP[github]=1; NEED_MCP[puppeteer]=1; NEED_MCP[dev-chrome]=1 ;;
      research)  NEED_MCP[brave-search]=1; NEED_MCP[puppeteer]=1; NEED_MCP[context7]=1; NEED_MCP[sqlite]=1 ;;
      auto-research-in-sleeping) NEED_MCP[brave-search]=1; NEED_MCP[puppeteer]=1; NEED_MCP[context7]=1; NEED_MCP[sqlite]=1 ;;
      analyst)   NEED_MCP[brave-search]=1; NEED_MCP[context7]=1; NEED_MCP[postgres]=1; NEED_MCP[sqlite]=1 ;;
      stock)     NEED_MCP[brave-search]=1; NEED_MCP[context7]=1 ;;
      marketing) NEED_MCP[brave-search]=1; NEED_MCP[excalidraw]=1 ;;
      daily)     NEED_MCP[brave-search]=1; NEED_MCP[context7]=1 ;;
      chat)      NEED_MCP[brave-search]=1; NEED_MCP[context7]=1 ;;
    esac
  done

  BRAVE_API_KEY=$(api_key_get "BRAVE_API_KEY" "BRAVE_API_KEY (leave empty to skip brave-search)" true)
  if [[ -z "$BRAVE_API_KEY" ]]; then
    log_warn "No BRAVE_API_KEY — skipping brave-search"
    unset "NEED_MCP[brave-search]"
  fi

  GITHUB_TOKEN=$(api_key_get "GITHUB_TOKEN" "GitHub Personal Access Token (leave empty to skip github)" true)
  if [[ -z "$GITHUB_TOKEN" ]]; then
    log_warn "No GitHub token — skipping github"
    unset "NEED_MCP[github]"
  fi

  POSTGRES_DSN=$(api_key_get "POSTGRES_DSN" "Postgres connection string (leave empty to skip)" false)
  if [[ -z "$POSTGRES_DSN" ]]; then
    log_warn "No Postgres DSN — skipping postgres"
    unset "NEED_MCP[postgres]"
  fi

  SQLITE_PATH="$HOME/data.db"
  if [[ -n "${NEED_MCP[sqlite]+x}" ]]; then
    read -r -p "SQLite DB path [${SQLITE_PATH}]: " _sqlite_input
    [[ -n "$_sqlite_input" ]] && SQLITE_PATH="$_sqlite_input"
  fi

  NEED_SERVERS="${!NEED_MCP[*]}"

  python3 - "$CODEX_CFG" "$NEED_SERVERS" \
      "$BRAVE_API_KEY" "$GITHUB_TOKEN" "$POSTGRES_DSN" "$SQLITE_PATH" << 'PYEOF'
import json
import pathlib
import re
import sys

codex_path = pathlib.Path(sys.argv[1])
servers    = sys.argv[2].split()
brave_key  = sys.argv[3]
gh_token   = sys.argv[4]
pg_dsn     = sys.argv[5]
sqlite_p   = sys.argv[6]

managed_names = {
    "context7", "excalidraw", "puppeteer", "github", "brave-search",
    "postgres", "sqlite", "claude-in-chrome",
}

def q(value):
    return json.dumps(value)

def server_block(name, command, args, env=None):
    lines = [f'[mcp_servers.{q(name)}]\n', f'command = {q(command)}\n']
    lines.append("args = [" + ", ".join(q(arg) for arg in args) + "]\n")
    if env:
        lines.append(f'\n[mcp_servers.{q(name)}.env]\n')
        for key, value in env.items():
            lines.append(f'{key} = {q(value)}\n')
    return lines

lines = codex_path.read_text().splitlines(True) if codex_path.exists() else []
table_re = re.compile(r'^\s*\[([^\]]+)\]\s*$')
out = []
skip = False
for line in lines:
    match = table_re.match(line)
    if match:
        table = match.group(1)
        skip = False
        for name in managed_names:
            quoted = q(name)
            if table in {f"mcp_servers.{quoted}", f"mcp_servers.{quoted}.env", f"mcp_servers.{name}", f"mcp_servers.{name}.env"}:
                skip = True
                break
    if not skip:
        out.append(line)

while out and not out[-1].strip():
    out.pop()

if 'context7' in servers:
    out.extend(["\n"] + server_block('context7', 'npx', ['-y', '@upstash/context7-mcp@latest']))
if 'excalidraw' in servers:
    out.extend(["\n"] + server_block('excalidraw', 'npx', ['-y', '@anthropic-ai/mcp-server-excalidraw']))
if 'puppeteer' in servers:
    out.extend(["\n"] + server_block('puppeteer', 'npx', ['-y', '@modelcontextprotocol/server-puppeteer']))
if 'github' in servers and gh_token:
    out.extend(["\n"] + server_block('github', 'npx', ['-y', '@modelcontextprotocol/server-github'], {'GITHUB_PERSONAL_ACCESS_TOKEN': gh_token}))
if 'brave-search' in servers and brave_key:
    out.extend(["\n"] + server_block('brave-search', 'npx', ['-y', '@modelcontextprotocol/server-brave-search'], {'BRAVE_API_KEY': brave_key}))
if 'postgres' in servers and pg_dsn:
    out.extend(["\n"] + server_block('postgres', 'npx', ['-y', '@modelcontextprotocol/server-postgres', pg_dsn]))
if 'sqlite' in servers:
    out.extend(["\n"] + server_block('sqlite', 'npx', ['-y', '@modelcontextprotocol/server-sqlite', '--db-path', sqlite_p]))
if 'dev-chrome' in servers:
    out.extend(["\n"] + server_block('claude-in-chrome', 'npx', ['-y', '@anthropic-ai/claude-in-chrome-mcp']))

codex_path.write_text("".join(out) + ("\n" if out else ""))
PYEOF

  log_info "Codex MCP config written to $CODEX_CFG"
fi

# =============================================
# 9. Skills Installation (existing)
# =============================================

SKILLS_SRC="${SCRIPT_DIR}/../skills"
SKILLS_TARGET="$HOME/.claude/skills"

_install_bundled_skill() {
  local name="$1"
  local source_dir="${SKILLS_SRC}/${name}"
  local target_dir="${SKILLS_TARGET}/${name}"

  if [[ ! -f "${source_dir}/SKILL.md" ]]; then
    log_warn "Missing skill template: ${source_dir}/SKILL.md"
    return
  fi

  mkdir -p "$SKILLS_TARGET"

  if [[ -d "$target_dir" ]]; then
    local backup_dir="${target_dir}.bak.$(date +%Y%m%d%H%M%S)"
    mv "$target_dir" "$backup_dir"
    log_warn "Existing skill backed up: ${backup_dir}"
  fi

  cp -R "$source_dir" "$target_dir"
  log_info "Installed skill: ${target_dir}"
}

_install_git_skill() {
  local name="$1" url="$2"
  local dest="${SKILLS_TARGET}/${name}"
  if [[ -z "$url" ]]; then
    log_warn "No URL for '${name}' -- skipping"
    return
  fi
  if [[ -d "${dest}/.git" ]]; then
    log_info "Updating skill: ${name}"
    git -C "$dest" pull --ff-only || log_warn "git pull failed for ${name}"
  else
    log_info "Installing skill: ${name}"
    git clone "$url" "$dest" || log_warn "git clone failed for ${name}"
  fi
}

# Only show skills menu when stdin is a terminal (interactive)
if command -v whiptail &>/dev/null && [[ -t 0 ]]; then
  SKILL_CHOICES=$(whiptail --title "codex Skills" --checklist \
    "Select skills to install (SPACE to toggle):" 16 70 6 \
    "figma-vibma"       "Vibma/Figma 连接工作流 (bundled)"        OFF \
    "figma-start-macos" "Figma macOS 会话启动器 (bundled)"        OFF \
    "superpowers"       "核心 superpowers 技能系统 (git)"         OFF \
    "ui-ux"             "UI/UX Pro Max 设计技能 (git)"            OFF \
    "ai-research"       "AI 自动调研 (git)"                       OFF \
    "anthropic-skills"  "Anthropic 官方技能集 (git)"              OFF \
    3>&1 1>&2 2>&3) || SKILL_CHOICES=""
  SKILL_SELECTED=$(echo "$SKILL_CHOICES" | tr -d '"')
else
  SKILL_SELECTED=""
fi

SKILLS_INSTALLED=0
for skill in $SKILL_SELECTED; do
  case "$skill" in
    figma-vibma)       _install_bundled_skill "figma-vibma"       ;;
    figma-start-macos) _install_bundled_skill "figma-start-macos" ;;
    superpowers)       read -r -p "superpowers repo URL: " _url
                       _install_git_skill "superpowers" "$_url"   ;;
    ui-ux)             read -r -p "ui-ux-pro-max repo URL: " _url
                       _install_git_skill "ui-ux" "$_url"         ;;
    ai-research)       read -r -p "ai-research repo URL: " _url
                       _install_git_skill "ai-research" "$_url"   ;;
    anthropic-skills)  read -r -p "anthropic-skills repo URL: " _url
                       _install_git_skill "anthropic-skills" "$_url" ;;
  esac
  SKILLS_INSTALLED=1
done

if [[ "$SKILLS_INSTALLED" -eq 1 ]]; then
  python3 - "$CODEX_CFG" "$SKILLS_TARGET" << 'PYEOF'
import json, sys, pathlib
path = pathlib.Path(sys.argv[1])
skills_dir = sys.argv[2]
lines = path.read_text().splitlines(True) if path.exists() else []
out = []
found = False
for line in lines:
    if line.startswith('skills_directory'):
        out.append(f'skills_directory = {json.dumps(skills_dir)}\n')
        found = True
    else:
        out.append(line)
if not found:
    if out and not out[-1].strip():
        out.append(f'skills_directory = {json.dumps(skills_dir)}\n')
    else:
        out.append(f'\nskills_directory = {json.dumps(skills_dir)}\n')
path.write_text("".join(out))
PYEOF
  log_info "skills_directory set to $SKILLS_TARGET"
fi

log_info "codex: done"
