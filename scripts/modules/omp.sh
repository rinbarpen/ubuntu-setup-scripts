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

# ---- OmniRoute provider + model -------------------------------------
OMP_PROVIDER="omniroute"
OMP_BASE_URL="http://localhost:20128/v1"
OMP_API_KEY_ENV="OMNIROUTE_API_KEY"
OMP_MODEL="omniroute/auto"
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
  MCHOICE=$(whiptail --title "omp Model" --menu "Select OmniRoute model:" 16 70 6 \
    "omniroute/auto"       "OmniRoute Auto" \
    "omniroute/auto/coding" "OmniRoute Coding" \
    "omniroute/auto/fast"  "OmniRoute Fast" \
    "inherit"              "Keep existing model" \
    3>&1 1>&2 2>&3) || MCHOICE="inherit"
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

provider = os.environ.get("OMP_PROVIDER", "omniroute")
model    = os.environ.get("OMP_MODEL", "omniroute/auto")
base_url = os.environ.get("OMP_BASE_URL", "http://localhost:20128/v1")
key_env  = os.environ.get("OMP_API_KEY_ENV", "OMNIROUTE_API_KEY")

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

log_info "omp settings written to $OMP_SETTINGS (OmniRoute: $OMP_BASE_URL; start with rinbake omniroute start if needed)"

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
