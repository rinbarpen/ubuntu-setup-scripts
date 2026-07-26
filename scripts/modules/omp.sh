#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"
source "${SCRIPT_DIR}/../lib/api.sh"
source "${SCRIPT_DIR}/../lib/mcp.sh"

OMP_CFG_DIR="$HOME/.pi/agent"
OMP_SETTINGS="$OMP_CFG_DIR/settings.json"

# ---- Install omp CLI ------------------------------------------------
install_omp() {

# Determine install method: prefer bun, fall back to npm
if command -v bun &>/dev/null; then
  _install_cmd="bun"
  _install_pkg="@oh-my-pi/pi-coding-agent"
else
  need_cmd npm
  _install_cmd="npm"
  _install_pkg="oh-my-pi"
fi

need_cmd python3

if command -v omp &>/dev/null; then
  log_info "omp already installed ($(command -v omp)), skipping install"
else
  log_info "Installing Oh-My-Pi (omp)..."
  if [[ "$_install_cmd" == "bun" ]]; then
    bun install -g "$_install_pkg"
  else
    npm install -g "$_install_pkg"
  fi
fi

mkdir -p "$OMP_CFG_DIR"

# Track installation status
if [[ -f "$OMP_CFG_DIR/.managed-by" ]]; then
  _existing=$(cat "$OMP_CFG_DIR/.managed-by" 2>/dev/null || echo "")
  case "$_existing" in
    pi)     echo "both" > "$OMP_CFG_DIR/.managed-by" ;;
    omp)    ;;  # already registered
    both)   ;;  # already registered
    *)      echo "omp" > "$OMP_CFG_DIR/.managed-by" ;;
  esac
else
  echo "omp" > "$OMP_CFG_DIR/.managed-by"
fi

# ---- Provider + Model (reads existing pi config if present) ----------
OMP_PROVIDER="deepseek"
OMP_BASE_URL="https://api.deepseek.com/v1"
OMP_API_KEY_ENV="DEEPSEEK_API_KEY"

if [[ -f "$OMP_SETTINGS" ]]; then
  _ep=$(python3 -c "
import json
try:
    c = json.load(open('$OMP_SETTINGS'))
    print(c.get('provider', ''))
except: pass
" 2>/dev/null || echo "")
  [[ -n "$_ep" ]] && OMP_PROVIDER="$_ep"
fi

if command -v whiptail &>/dev/null; then
  _prov_info="当前: ${OMP_PROVIDER}"
  OMP_CHOICE=$(whiptail --title "omp Provider" --menu "Select default provider:\n${_prov_info}" 22 70 10 \
    "deepseek"    "DeepSeek (api.deepseek.com)" \
    "openai"      "OpenAI (api.openai.com)" \
    "openrouter"  "OpenRouter (openrouter.ai)" \
    "aihubmix"    "AIHubMix (aihubmix.com)" \
    "anthropic"   "Anthropic (api.anthropic.com)" \
    "google"      "Google Gemini" \
    "ollama"      "Ollama (local)" \
    "inherit"     "Inherit from existing config" \
    3>&1 1>&2 2>&3) || OMP_CHOICE="inherit"
  [[ -n "$OMP_CHOICE" && "$OMP_CHOICE" != "inherit" ]] && OMP_PROVIDER="$OMP_CHOICE"
fi

if [[ "$OMP_PROVIDER" != "inherit" ]]; then
  case "$OMP_PROVIDER" in
    deepseek)
      OMP_BASE_URL="https://api.deepseek.com/v1"
      OMP_API_KEY_ENV="DEEPSEEK_API_KEY"
      api_key_get "$OMP_API_KEY_ENV" "DeepSeek API Key" true
      ;;
    openai)
      OMP_BASE_URL="https://api.openai.com/v1"
      OMP_API_KEY_ENV="OPENAI_API_KEY"
      api_key_get "$OMP_API_KEY_ENV" "OpenAI API Key" true
      ;;
    openrouter)
      OMP_BASE_URL="https://openrouter.ai/api/v1"
      OMP_API_KEY_ENV="OPENROUTER_API_KEY"
      api_key_get "$OMP_API_KEY_ENV" "OpenRouter API Key" true
      ;;
    aihubmix)
      OMP_BASE_URL="https://aihubmix.com/v1"
      OMP_API_KEY_ENV="AIHUBMIX_API_KEY"
      api_key_get "$OMP_API_KEY_ENV" "AIHubMix API Key" true
      ;;
    anthropic)
      OMP_BASE_URL="https://api.anthropic.com/v1"
      OMP_API_KEY_ENV="ANTHROPIC_API_KEY"
      api_key_get "$OMP_API_KEY_ENV" "Anthropic API Key" true
      ;;
    google)
      OMP_BASE_URL="https://generativelanguage.googleapis.com/v1beta"
      OMP_API_KEY_ENV="GOOGLE_API_KEY"
      api_key_get "$OMP_API_KEY_ENV" "Google API Key" true
      ;;
    ollama)
      OMP_BASE_URL="http://localhost:11434/v1"
      OMP_API_KEY_ENV=""
      ;;
  esac
fi

# Model selection
OMP_MODEL="deepseek-v4-pro"
if [[ -f "$OMP_SETTINGS" ]]; then
  _em=$(python3 -c "
import json
try:
    c = json.load(open('$OMP_SETTINGS'))
    print(c.get('model', ''))
except: pass
" 2>/dev/null || echo "")
  [[ -n "$_em" ]] && OMP_MODEL="$_em"
fi

if command -v whiptail &>/dev/null; then
  case "$OMP_PROVIDER" in
    deepseek)
      _model_info="当前: ${OMP_MODEL}"
      MCHOICE=$(whiptail --title "omp Model" --menu "Select model:\n${_model_info}" 18 70 8 \
        "deepseek-v4-pro"   "DeepSeek V4 Pro (recommended for omp)" \
        "deepseek-v4-flash" "DeepSeek V4 Flash (fast & cheap)" \
        "deepseek-chat"     "DeepSeek V3 Chat" \
        "deepseek-reasoner" "DeepSeek Reasoner (R1)" \
        "inherit"           "Keep existing model" \
        3>&1 1>&2 2>&3) || MCHOICE="inherit"
      ;;
    openai)
      _model_info="当前: ${OMP_MODEL}"
      MCHOICE=$(whiptail --title "omp Model" --menu "Select model:\n${_model_info}" 18 70 8 \
        "gpt-5.5"       "GPT-5.5" \
        "gpt-4o"        "GPT-4o" \
        "gpt-4o-mini"   "GPT-4o Mini" \
        "inherit"       "Keep existing model" \
        3>&1 1>&2 2>&3) || MCHOICE="inherit"
      ;;
    openrouter)
      _model_info="当前: ${OMP_MODEL}"
      MCHOICE=$(whiptail --title "omp Model" --menu "Select model:\n${_model_info}" 20 70 8 \
        "openai/gpt-5.5"                    "GPT-5.5" \
        "openai/gpt-4o"                     "GPT-4o" \
        "anthropic/claude-sonnet-4-20250514" "Claude Sonnet 4" \
        "deepseek/deepseek-v4-pro"           "DeepSeek V4 Pro" \
        "inherit"                            "Keep existing model" \
        3>&1 1>&2 2>&3) || MCHOICE="inherit"
      ;;
    *)
      MCHOICE="inherit"
      ;;
  esac
  [[ -n "${MCHOICE:-}" && "$MCHOICE" != "inherit" ]] && OMP_MODEL="$MCHOICE"
fi

# ---- omp feature toggles --------------------------------------------
OMP_HASH_EDITS="true"
OMP_SNAPCOMPACT="true"
OMP_LSP="false"
OMP_DAP="false"
OMP_SUBAGENTS="false"

# Read existing feature settings
if [[ -f "$OMP_SETTINGS" ]]; then
  _feats=$(python3 -c "
import json
try:
    c = json.load(open('$OMP_SETTINGS'))
    f = c.get('features', {})
    print(f.get('hashAnchoredEdits','true') + '|' +
          f.get('snapcompact','true') + '|' +
          f.get('lsp','false') + '|' +
          f.get('dap','false') + '|' +
          f.get('subagentSystem','false'))
except: pass
" 2>/dev/null || echo "")
  if [[ -n "$_feats" ]]; then
    IFS='|' read -r OMP_HASH_EDITS OMP_SNAPCOMPACT OMP_LSP OMP_DAP OMP_SUBAGENTS <<< "$_feats"
  fi
fi

if command -v whiptail &>/dev/null; then
  FEAT_CHOICES=$(whiptail --title "omp Features" --checklist \
    "Select omp features (SPACE to toggle):" 16 70 5 \
    "hashAnchoredEdits" "Hash-anchored edits (reduces output tokens ~61%)" ON \
    "snapcompact"       "Deterministic context compaction"                  ON \
    "lsp"               "LSP integration (53+ language servers)"            OFF \
    "dap"               "DAP debugger (lldb, dlv, debugpy, js-debug)"      OFF \
    "subagentSystem"    "6 bundled agents with isolated git worktrees"      OFF \
    3>&1 1>&2 2>&3) || FEAT_CHOICES="hashAnchoredEdits snapcompact"
  FEAT_SEL=$(echo "$FEAT_CHOICES" | tr -d '"')

  OMP_HASH_EDITS="false"
  OMP_SNAPCOMPACT="false"
  OMP_LSP="false"
  OMP_DAP="false"
  OMP_SUBAGENTS="false"
  for _feat in $FEAT_SEL; do
    case "$_feat" in
      hashAnchoredEdits) OMP_HASH_EDITS="true" ;;
      snapcompact)       OMP_SNAPCOMPACT="true" ;;
      lsp)               OMP_LSP="true" ;;
      dap)               OMP_DAP="true" ;;
      subagentSystem)    OMP_SUBAGENTS="true" ;;
    esac
  done
fi

export OMP_PROVIDER OMP_BASE_URL OMP_API_KEY_ENV OMP_MODEL
export OMP_HASH_EDITS OMP_SNAPCOMPACT OMP_LSP OMP_DAP OMP_SUBAGENTS

# ---- Write/merge settings.json --------------------------------------
python3 - "$OMP_SETTINGS" << 'PYEOF'
import json, os, pathlib, sys

path = pathlib.Path(sys.argv[1])

# Read existing config (may have been written by pi.sh)
try:
    config = json.loads(path.read_text())
except Exception:
    config = {}

provider = os.environ.get("OMP_PROVIDER", "")
model    = os.environ.get("OMP_MODEL", "")
base_url = os.environ.get("OMP_BASE_URL", "")
key_env  = os.environ.get("OMP_API_KEY_ENV", "")

# Only overwrite if user explicitly selected a new provider/model
if provider and provider != "inherit":
    config["provider"] = provider
    config["baseUrl"]  = base_url
    if key_env:
        config["apiKey"] = f"{{env:{key_env}}}"

if model and model != "inherit":
    config["model"] = model

# omp-specific features (additive — preserves any pi-specific keys)
config["features"] = {
    "hashAnchoredEdits": os.environ.get("OMP_HASH_EDITS", "true") == "true",
    "snapcompact":       os.environ.get("OMP_SNAPCOMPACT", "true") == "true",
    "lsp":               os.environ.get("OMP_LSP", "false") == "true",
    "dap":               os.environ.get("OMP_DAP", "false") == "true",
    "subagentSystem":    os.environ.get("OMP_SUBAGENTS", "false") == "true",
}

# Cache optimization settings
config.setdefault("cache", {}).update({
    "hashAnchoredEdits": config["features"]["hashAnchoredEdits"],
    "consistentSystemPrompts": True,
    "minimizeOutputTokens": True,
})

# Ensure autoLoad is present (pi uses it)
config.setdefault("autoLoad", ["CLAUDE.md", "AGENTS.md"])

path.write_text(json.dumps(config, indent=2) + "\n")
print(f"omp settings written to {path}")
PYEOF

log_info "omp settings written to $OMP_SETTINGS"

# ---- MCP Toolkits ---------------------------------------------------
SCENARIOS=$(mcp_select_scenarios "omp MCP Toolkits")
if [[ -n "$SCENARIOS" ]]; then
  CREDS=$(mcp_collect_credentials "$SCENARIOS")
  mcp_write_json "$OMP_SETTINGS" "mcpServers" "$SCENARIOS" "$CREDS"
  log_info "omp MCP servers written to $OMP_SETTINGS"
fi

# ---- Shell helper functions -----------------------------------------
FISH_FUNC_DIR="$HOME/.config/fish/functions"
mkdir -p "$FISH_FUNC_DIR"

cat > "${FISH_FUNC_DIR}/omp_env.fish" << 'FEOF'
function omp_env
    set -l key_file ~/.config/rinbarpen/api-keys.env
    if test -f $key_file
        bass source $key_file
        echo "omp environment loaded from $key_file"
    else
        echo "No api-keys.env found at $key_file"
        return 1
    end
end
FEOF
log_info "Fish function: omp_env"

if ! grep -q "# omp-env (added by setup)" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" << 'BASHEOF'

# omp-env (added by setup)
omp-env() {
  local f="$HOME/.config/rinbarpen/api-keys.env"
  if [[ -f "$f" ]]; then
    # shellcheck source=/dev/null
    source "$f"
    echo "omp environment loaded from $f"
  else
    echo "No api-keys.env found at $f"
    return 1
  fi
}
BASHEOF
  log_info "Bash function: omp-env"
fi

log_info "omp: done"
}

install_omp "$@"
