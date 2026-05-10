#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"
source "${SCRIPT_DIR}/../lib/api.sh"

need_cmd npm

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

# Codex model selection
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
  [[ -n "$_existing_model" ]] && CODEX_MODEL="$_existing_model" && log_info "Existing model: $CODEX_MODEL"
fi

if command -v whiptail &>/dev/null; then
  _model_info="当前: ${CODEX_MODEL:-未设置}"
  CHOICE=$(whiptail --title "Codex Model" --menu "Select default model for Codex:\n${_model_info}" 20 75 10 \
      "do-not-set"    "Do not set model (use plan mode for reasoning)" \
      "deepseek-v4-pro" "DeepSeek V4 Pro" \
      "deepseek-v4-flash" "DeepSeek V4 Flash (for plan mode)" \
      "custom" "Custom model ID" \
      3>&1 1>&2 2>&3) || CHOICE=""

  case "$CHOICE" in
    do-not-set) CODEX_MODEL="" ;;
    deepseek-v4-pro|deepseek-v4-flash) CODEX_MODEL="$CHOICE" ;;
    custom) read -r -p "Enter model ID: " CODEX_MODEL ;;
    *) ;;  # keep existing / default
  esac
fi
export CODEX_MODEL

# Plan mode model selection (defaults to better model for deep reasoning)
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
  PLAN_CHOICE=$(whiptail --title "Codex Plan Model" --menu "Select model for Plan mode (deep reasoning):\n${_plan_info}" 20 75 10 \
      "deepseek-v4-pro" "DeepSeek V4 Pro (推荐)" \
      "deepseek-v4-flash" "DeepSeek V4 Flash (快但稍弱)" \
      "custom" "Custom model ID" \
      3>&1 1>&2 2>&3) || PLAN_CHOICE=""

  case "$PLAN_CHOICE" in
    deepseek-v4-pro|deepseek-v4-flash) CODEX_PLAN_MODEL="$PLAN_CHOICE" ;;
    custom) read -r -p "Enter plan model ID: " CODEX_PLAN_MODEL ;;
    *) ;;  # keep existing default
  esac
fi
export CODEX_PLAN_MODEL

# Approval policy selection (= permission mode equivalent for codex)
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

# Write codex defaults
python3 - "$CODEX_CFG" << 'PYEOF'
import json
import pathlib
import re
import sys
import os

path = pathlib.Path(sys.argv[1])
approval_policy = os.environ.get("CODEX_APPROVAL", "on-request")
managed = {
    "model_reasoning_effort": "medium",
    "plan_mode_reasoning_effort": "xhigh",
    "approval_policy": approval_policy,
    "sandbox_mode": "workspace-write",
}

# Only add model if user selected one
codex_model = os.environ.get("CODEX_MODEL")
if codex_model:
    managed["model"] = codex_model
    # DeepSeek models need custom base URL (OpenAI format)
    if "deepseek" in codex_model.lower():
        managed["openai_base_url"] = "https://api.deepseek.com"

# Add plan mode model (separate from default model)
codex_plan_model = os.environ.get("CODEX_PLAN_MODEL")
if codex_plan_model:
    managed["plan_model"] = codex_plan_model

lines = path.read_text().splitlines(True) if path.exists() else []
key_re = re.compile(r"^\s*([A-Za-z0-9_-]+)\s*=")
table_re = re.compile(r"^\s*\[")

top, rest = [], []
in_tables = False
for line in lines:
    if table_re.match(line):
        in_tables = True
    if in_tables:
        rest.append(line)
        continue
    match = key_re.match(line)
    if match and match.group(1) in managed:
        continue
    top.append(line)

while top and not top[-1].strip():
    top.pop()

out = top[:]
if out:
    out.append("\n")
for key, value in managed.items():
    out.append(f"{key} = {json.dumps(value)}\n")
if rest:
    if out and out[-1].strip():
        out.append("\n")
    out.extend(rest)

path.write_text("".join(out))
PYEOF
log_info "Codex defaults written to $CODEX_CFG"

# codex-auth function
FISH_FUNC_DIR="$HOME/.config/fish/functions"
mkdir -p "$FISH_FUNC_DIR"

cat > "${FISH_FUNC_DIR}/codex_auth.fish" << 'EOF'
function codex_auth
    read -s -P "Enter OPENAI_API_KEY: " key
    set -gx OPENAI_API_KEY $key
    echo ""
    echo "OPENAI_API_KEY set for this session"
end
EOF

if ! grep -q "# codex-auth (added by setup)" "$HOME/.bashrc" 2>/dev/null; then
cat >> "$HOME/.bashrc" << 'BASHEOF'

# codex-auth (added by setup)
codex-auth() {
  read -r -s -p "Enter OPENAI_API_KEY: " key
  echo ""
  export OPENAI_API_KEY="$key"
  echo "OPENAI_API_KEY set for this session"
}
BASHEOF
fi

# MCP Toolkits — scenario-based selection (for codex)

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
