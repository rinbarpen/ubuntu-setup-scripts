#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"
source "${SCRIPT_DIR}/../lib/api.sh"

need_cmd npm

CLAUDE_SETTINGS="$HOME/.claude/settings.json"

# Install Claude Code CLI (skip if already installed)
if command -v claude &>/dev/null; then
  log_info "Claude Code already installed ($(command -v claude)), skipping npm install"
else
  log_info "Installing Claude Code..."
  npm install -g @anthropic-ai/claude-code
fi

mkdir -p "$(dirname "$CLAUDE_SETTINGS")"

# Claude Code model selection (DeepSeek only)
CLAUDE_MODEL="deepseek-v4-pro"
if [[ -f "$CLAUDE_SETTINGS" ]]; then
  _existing_model=$(python3 -c "import json; print(json.load(open('$CLAUDE_SETTINGS')).get('model',''))" 2>/dev/null || echo "")
  [[ -n "$_existing_model" ]] && CLAUDE_MODEL="$_existing_model"
fi

if command -v whiptail &>/dev/null; then
  _model_info="当前: ${CLAUDE_MODEL}"
  CHOICE=$(whiptail --title "Claude Code Model" --menu "Select default model:\n${_model_info}" 20 75 10 \
      "deepseek-v4-pro" "DeepSeek V4 Pro" \
      "deepseek-v4-flash" "DeepSeek V4 Flash" \
      "custom" "Custom model ID" \
      3>&1 1>&2 2>&3) || CHOICE=""

  case "$CHOICE" in
    deepseek-v4-pro|deepseek-v4-flash) CLAUDE_MODEL="$CHOICE" ;;
    custom) read -r -p "Enter model ID: " CLAUDE_MODEL ;;
    *) ;;  # keep existing default
  esac
fi
export CLAUDE_MODEL

# Plan mode model selection (defaults to a better model for deep reasoning)
CLAUDE_PLAN_MODEL="deepseek-v4-pro"
if [[ -f "$CLAUDE_SETTINGS" ]]; then
  _existing_plan_model=$(python3 -c "
import json
try:
    s = json.load(open('$CLAUDE_SETTINGS'))
    env = s.get('env', {})
    print(env.get('ANTHROPIC_DEFAULT_OPUS_MODEL', ''))
except: pass
" 2>/dev/null || echo "")
  [[ -n "$_existing_plan_model" ]] && CLAUDE_PLAN_MODEL="$_existing_plan_model"
fi

if command -v whiptail &>/dev/null; then
  _plan_info="当前: ${CLAUDE_PLAN_MODEL}"
  PLAN_CHOICE=$(whiptail --title "Claude Code Plan Model" --menu "Select model for Plan mode (deep reasoning):\n${_plan_info}" 20 75 10 \
      "deepseek-v4-pro" "DeepSeek V4 Pro (推荐)" \
      "deepseek-v4-flash" "DeepSeek V4 Flash (快但稍弱)" \
      "custom" "Custom model ID" \
      3>&1 1>&2 2>&3) || PLAN_CHOICE=""

  case "$PLAN_CHOICE" in
    deepseek-v4-pro|deepseek-v4-flash) CLAUDE_PLAN_MODEL="$PLAN_CHOICE" ;;
    custom) read -r -p "Enter plan model ID: " CLAUDE_PLAN_MODEL ;;
    *) ;;  # keep existing default
  esac
fi
export CLAUDE_PLAN_MODEL

# Permission mode selection
PERM_MODE="acceptEdits"
if [[ -f "$CLAUDE_SETTINGS" ]]; then
  _existing_perm=$(python3 -c "import json; print(json.load(open('$CLAUDE_SETTINGS')).get('permissions',{}).get('defaultMode',''))" 2>/dev/null || echo "")
  [[ -n "$_existing_perm" ]] && PERM_MODE="$_existing_perm"
fi

if command -v whiptail &>/dev/null; then
  _perm_info="当前: ${PERM_MODE}"
  PERM_CHOICE=$(whiptail --title "Permission Mode" --menu "Select default permission mode:\n${_perm_info}" 18 70 4 \
    "default"      "每次询问 (Ask every time)" \
    "acceptEdits"  "自动接受编辑 (Auto-accept edits)" \
    "bypass"       "绕过权限检查 (Bypass all checks)" \
    3>&1 1>&2 2>&3) || PERM_CHOICE=""

  case "$PERM_CHOICE" in
    default|acceptEdits|bypass) PERM_MODE="$PERM_CHOICE" ;;
    *) ;;  # keep existing default
  esac
fi
export PERM_MODE

python3 - "$CLAUDE_SETTINGS" << 'PYEOF'
import json
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
old_allow = ['Bash(*)', 'Read(*)', 'Write(*)', 'Edit(*)', 'Glob(*)', 'Grep(*)']

try:
    settings = json.loads(path.read_text())
except Exception:
    settings = {}

# Set model if user selected one
if os.environ.get("CLAUDE_MODEL"):
    settings["model"] = os.environ.get("CLAUDE_MODEL")

# Env for third-party API providers (DeepSeek etc.): CLAUDE_CODE_ATTRIBUTION_HEADER=0 is required;
# first two reduce response latency; ENABLE_TOOL_SEARCH + DISABLE_EXTRA_USAGE_COMMAND
# are general Claude Code optimizations
env = settings.setdefault("env", {})
env.setdefault("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "1")
env.setdefault("CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK", "1")
env.setdefault("CLAUDE_CODE_ATTRIBUTION_HEADER", "0")
env.setdefault("ENABLE_TOOL_SEARCH", "1")
env.setdefault("DISABLE_EXTRA_USAGE_COMMAND", "1")
# DeepSeek model routing defaults (only set when model is selected)
model = os.environ.get("CLAUDE_MODEL", "")
if model:
    env.setdefault("ANTHROPIC_MODEL", model)
    env.setdefault("ANTHROPIC_DEFAULT_SONNET_MODEL", "deepseek-v4-flash")
    env.setdefault("ANTHROPIC_DEFAULT_HAIKU_MODEL", "deepseek-v4-flash")
    env.setdefault("CLAUDE_CODE_SUBAGENT_MODEL", "deepseek-v4-flash")
env.setdefault("CLAUDE_CODE_MAX_OUTPUT_TOKENS", "1000000")
env.setdefault("CLAUDE_CODE_EFFORT_LEVEL", "max")
plan_model = os.environ.get("CLAUDE_PLAN_MODEL")
if plan_model:
    env["ANTHROPIC_DEFAULT_OPUS_MODEL"] = plan_model

permissions = settings.setdefault("permissions", {})
if permissions.get("allow") == old_allow and permissions.get("deny") == []:
    permissions.pop("allow", None)
    permissions.pop("deny", None)
perm_mode = os.environ.get("PERM_MODE", "acceptEdits")
permissions["defaultMode"] = perm_mode
if perm_mode == "bypass":
    permissions.pop("allow", None)
    permissions.pop("deny", None)
    permissions.pop("denyRules", None)

path.write_text(json.dumps(settings, indent=2) + "\n")
PYEOF
log_info "Claude Code default model and permission mode written to $CLAUDE_SETTINGS"

# Provider profiles
PROFILES_DIR="$HOME/.config/cc-profiles"
mkdir -p "$PROFILES_DIR"

_ep=$(ls "$PROFILES_DIR"/*.env 2>/dev/null | xargs -I{} basename {} .env || echo "")
if [[ -n "$_ep" ]]; then
  log_info "Existing provider profiles:"
  for _p in $_ep; do echo "  - $_p"; done
fi

while confirm "Add a provider profile for Claude Code?"; do
  echo "Providers: anthropic / openrouter / deepseek / custom"
  read -r -p "Provider name: " PROVIDER
  read -r -s -p "API key: " API_KEY; echo ""

  case "$PROVIDER" in
    anthropic)
      cat > "${PROFILES_DIR}/${PROVIDER}.env" << EOF
export ANTHROPIC_API_KEY="${API_KEY}"
EOF
      ;;
    openrouter)
      cat > "${PROFILES_DIR}/${PROVIDER}.env" << EOF
export ANTHROPIC_API_KEY="${API_KEY}"
export ANTHROPIC_BASE_URL="https://openrouter.ai/api/v1"
EOF
      ;;
    deepseek)
      cat > "${PROFILES_DIR}/${PROVIDER}.env" << EOF
export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
export ANTHROPIC_API_KEY="${API_KEY}"
EOF
      ;;
    custom)
      read -r -p "API base URL: " BASE_URL
      cat > "${PROFILES_DIR}/${PROVIDER}.env" << EOF
export ANTHROPIC_API_KEY="${API_KEY}"
export ANTHROPIC_BASE_URL="${BASE_URL}"
EOF
      ;;
    *)
      log_warn "Unknown provider '$PROVIDER', writing as custom (ANTHROPIC_API_KEY only)"
      cat > "${PROFILES_DIR}/${PROVIDER}.env" << EOF
export ANTHROPIC_API_KEY="${API_KEY}"
EOF
      ;;
  esac
  log_info "Profile saved: ${PROFILES_DIR}/${PROVIDER}.env"
done

# cc-switch function
FISH_FUNC_DIR="$HOME/.config/fish/functions"
mkdir -p "$FISH_FUNC_DIR"

cat > "${FISH_FUNC_DIR}/cc_switch.fish" << 'EOF'
function cc_switch
    if test -z "$argv[1]"
        echo "Usage: cc_switch <profile>"
        echo "Available profiles:"
        ls ~/.config/cc-profiles/*.env 2>/dev/null | xargs -I{} basename {} .env
        return 1
    end
    set profile_file ~/.config/cc-profiles/$argv[1].env
    if not test -f $profile_file
        echo "Profile not found: $argv[1]"
        echo "Available:"
        ls ~/.config/cc-profiles/*.env 2>/dev/null | xargs -I{} basename {} .env
        return 1
    end
    bass source $profile_file
    echo "Switched to profile: $argv[1]"
end
EOF

# bash equivalent (guard against duplicate entries)
if ! grep -q "# cc-switch (added by setup)" "$HOME/.bashrc" 2>/dev/null; then
cat >> "$HOME/.bashrc" << 'BASHEOF'

# cc-switch (added by setup)
cc-switch() {
  local profile="${1:-}"
  if [[ -z "$profile" ]]; then
    echo "Usage: cc-switch <profile>"
    ls ~/.config/cc-profiles/*.env 2>/dev/null | xargs -I{} basename {} .env
    return 1
  fi
  local f="$HOME/.config/cc-profiles/${profile}.env"
  if [[ ! -f "$f" ]]; then
    echo "Profile not found: $profile"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$f"
  echo "Switched to profile: $profile"
}
BASHEOF
fi

# MCP Toolkits — scenario-based selection (for Claude Code)

# Show existing MCP servers if any
if [[ -f "$CLAUDE_SETTINGS" ]]; then
  _existing_mcp=$(python3 -c "
import json
try:
    s = json.load(open('$CLAUDE_SETTINGS'))
    mcps = s.get('mcpServers', {})
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
  SCENARIO_CHOICES=$(whiptail --title "MCP Toolkits (Claude Code)" --checklist \
      "Select toolkits to configure for Claude Code (SPACE to toggle):" 20 65 11 \
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
  log_warn "whiptail not found — skipping MCP toolkit selection for Claude Code"
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

  python3 - "$CLAUDE_SETTINGS" "$NEED_SERVERS" \
      "$BRAVE_API_KEY" "$GITHUB_TOKEN" "$POSTGRES_DSN" "$SQLITE_PATH" << 'PYEOF'
import json, sys

path      = sys.argv[1]
servers   = sys.argv[2].split()
brave_key = sys.argv[3]
gh_token  = sys.argv[4]
pg_dsn    = sys.argv[5]
sqlite_p  = sys.argv[6]

try:
    with open(path) as f:
        s = json.load(f)
except Exception:
    s = {}

mcp = s.setdefault('mcpServers', {})

if 'context7' in servers:
    mcp['context7'] = {
        'type': 'stdio', 'command': 'npx',
        'args': ['-y', '@upstash/context7-mcp@latest']
    }
if 'excalidraw' in servers:
    mcp['excalidraw'] = {
        'type': 'stdio', 'command': 'npx',
        'args': ['-y', '@anthropic-ai/mcp-server-excalidraw']
    }
if 'puppeteer' in servers:
    mcp['puppeteer'] = {
        'type': 'stdio', 'command': 'npx',
        'args': ['-y', '@modelcontextprotocol/server-puppeteer']
    }
if 'github' in servers and gh_token:
    mcp['github'] = {
        'type': 'stdio', 'command': 'npx',
        'args': ['-y', '@modelcontextprotocol/server-github'],
        'env': {'GITHUB_PERSONAL_ACCESS_TOKEN': gh_token}
    }
if 'brave-search' in servers and brave_key:
    mcp['brave-search'] = {
        'type': 'stdio', 'command': 'npx',
        'args': ['-y', '@modelcontextprotocol/server-brave-search'],
        'env': {'BRAVE_API_KEY': brave_key}
    }
if 'postgres' in servers and pg_dsn:
    mcp['postgres'] = {
        'type': 'stdio', 'command': 'npx',
        'args': ['-y', '@modelcontextprotocol/server-postgres', pg_dsn]
    }
if 'sqlite' in servers:
    mcp['sqlite'] = {
        'type': 'stdio', 'command': 'npx',
        'args': ['-y', '@modelcontextprotocol/server-sqlite', '--db-path', sqlite_p]
    }
if 'dev-chrome' in servers:
    mcp['claude-in-chrome'] = {
        'type': 'stdio', 'command': 'npx',
        'args': ['-y', '@anthropic-ai/claude-in-chrome-mcp']
    }

with open(path, 'w') as f:
    json.dump(s, f, indent=2)
    f.write('\n')
PYEOF

  log_info "MCP toolkit servers written to $CLAUDE_SETTINGS"
fi

# Skills installation
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
  SKILL_CHOICES=$(whiptail --title "Claude Code Skills" --checklist \
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
  python3 - "$CLAUDE_SETTINGS" "$SKILLS_TARGET" << 'PYEOF'
import json, sys
path, skills_dir = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        s = json.load(f)
except Exception:
    s = {}
if s.get('skillsDirectory') != skills_dir:
    s['skillsDirectory'] = skills_dir
    with open(path, 'w') as f:
        json.dump(s, f, indent=2)
        f.write('\n')
    print("skillsDirectory updated")
PYEOF
  log_info "skillsDirectory set to $SKILLS_TARGET"
fi

log_info "claude-code: done"
