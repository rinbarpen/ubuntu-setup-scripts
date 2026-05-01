#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

need_cmd npm

CLAUDE_SETTINGS="$HOME/.claude/settings.json"

# Install Claude Code CLI
log_info "Installing Claude Code..."
npm install -g @anthropic-ai/claude-code

mkdir -p "$(dirname "$CLAUDE_SETTINGS")"

# Claude Code model selection (DeepSeek only)
CLAUDE_MODEL=""
if command -v whiptail &>/dev/null; then
  CHOICE=$(whiptail --title "Claude Code Model" --menu "Select default model for Claude Code:" 20 75 10 \
      "deepseek-v4-pro" "DeepSeek V4 Pro" \
      "deepseek-v4-flash" "DeepSeek V4 Flash" \
      "custom" "Custom model ID" \
      3>&1 1>&2 2>&3) || CHOICE="deepseek-v4-pro"

  [[ "$CHOICE" == "custom" ]] && read -r -p "Enter model ID: " CHOICE
  CLAUDE_MODEL="$CHOICE"
fi
export CLAUDE_MODEL

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

permissions = settings.setdefault("permissions", {})
if permissions.get("allow") == old_allow and permissions.get("deny") == []:
    permissions.pop("allow", None)
    permissions.pop("deny", None)
permissions["defaultMode"] = "acceptEdits"

path.write_text(json.dumps(settings, indent=2) + "\n")
PYEOF
log_info "Claude Code default model and permission mode written to $CLAUDE_SETTINGS"

# Provider profiles
PROFILES_DIR="$HOME/.config/cc-profiles"
mkdir -p "$PROFILES_DIR"

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
if command -v whiptail &>/dev/null; then
  SCENARIO_CHOICES=$(whiptail --title "MCP Toolkits (Claude Code)" --checklist \
      "Select toolkits to configure for Claude Code (SPACE to toggle):" 20 65 8 \
      "frontend"   "前端开发: context7, excalidraw, puppeteer"  OFF \
      "backend"    "后端开发: context7, github, postgres, sqlite" OFF \
      "testing"    "测试:     context7, github, puppeteer"       OFF \
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
      frontend)  NEED_MCP[context7]=1; NEED_MCP[excalidraw]=1; NEED_MCP[puppeteer]=1; NEED_MCP[dev-chrome]=1 ;;
      backend)   NEED_MCP[context7]=1; NEED_MCP[github]=1; NEED_MCP[postgres]=1; NEED_MCP[sqlite]=1 ;;
      testing)   NEED_MCP[context7]=1; NEED_MCP[github]=1; NEED_MCP[puppeteer]=1; NEED_MCP[dev-chrome]=1 ;;
      analyst)   NEED_MCP[brave-search]=1; NEED_MCP[context7]=1; NEED_MCP[postgres]=1; NEED_MCP[sqlite]=1 ;;
      stock)     NEED_MCP[brave-search]=1; NEED_MCP[context7]=1 ;;
      marketing) NEED_MCP[brave-search]=1; NEED_MCP[excalidraw]=1 ;;
      daily)     NEED_MCP[brave-search]=1; NEED_MCP[context7]=1 ;;
      chat)      NEED_MCP[brave-search]=1; NEED_MCP[context7]=1 ;;
    esac
  done

  BRAVE_API_KEY=""
  if [[ -n "${NEED_MCP[brave-search]+x}" ]]; then
    read -r -p "BRAVE_API_KEY (leave empty to skip brave-search): " BRAVE_API_KEY
    [[ -z "$BRAVE_API_KEY" ]] && log_warn "No BRAVE_API_KEY — skipping brave-search" && unset "NEED_MCP[brave-search]"
  fi

  GITHUB_TOKEN=""
  if [[ -n "${NEED_MCP[github]+x}" ]]; then
    read -r -s -p "GitHub Personal Access Token (leave empty to skip github): " GITHUB_TOKEN; echo ""
    [[ -z "$GITHUB_TOKEN" ]] && log_warn "No GitHub token — skipping github" && unset "NEED_MCP[github]"
  fi

  POSTGRES_DSN=""
  if [[ -n "${NEED_MCP[postgres]+x}" ]]; then
    read -r -p "Postgres connection string (leave empty to skip): " POSTGRES_DSN
    [[ -z "$POSTGRES_DSN" ]] && log_warn "No Postgres DSN — skipping postgres" && unset "NEED_MCP[postgres]"
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

log_info "claude-code: done"
