#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

need_cmd npm
need_cmd python3

OPEN_CODE_CFG="$HOME/.config/opencode/opencode.json"

log_info "Installing opencode..."
npm install -g opencode-ai

mkdir -p "$(dirname "$OPEN_CODE_CFG")"

# Model selection
DEFAULT_MODEL="deepseek/deepseek-v4-flash"
PLAN_MODEL="openai/gpt-5.5"

if command -v whiptail &>/dev/null; then
  CHOICE=$(whiptail --title "opencode Default Model" --menu "Select default chat model:" 20 70 10 \
    "deepseek/deepseek-v4-flash" "DeepSeek V4 Flash (fast & cheap)" \
    "deepseek/deepseek-v4-pro" "DeepSeek V4 Pro (enhanced capability)" \
    "deepseek/deepseek-chat" "DeepSeek V3 Chat" \
    "openai/gpt-5.5" "OpenAI GPT-5.5" \
    "openai/gpt-4o" "OpenAI GPT-4o" \
    "openrouter/anthropic/claude-3.5-sonnet" "Claude 3.5 Sonnet (via OpenRouter)" \
    "custom" "Custom model string" \
    3>&1 1>&2 2>&3) || CHOICE="deepseek/deepseek-v4-flash"
  
  [[ "$CHOICE" == "custom" ]] && read -r -p "Enter custom model (provider/model): " CHOICE
  DEFAULT_MODEL="$CHOICE"
  
  # Plan model selection
  CHOICE=$(whiptail --title "opencode Plan Model" --menu "Select Plan model:" 15 70 6 \
    "openai/gpt-5.5" "OpenAI GPT-5.5 (default)" \
    "openai/o1-preview" "O1 Preview" \
    "openai/o1-mini" "O1 Mini" \
    "deepseek/deepseek-reasoner" "DeepSeek Reasoner" \
    "custom" "Custom" \
    3>&1 1>&2 2>&3) || CHOICE="openai/gpt-5.5"
    
  [[ "$CHOICE" == "custom" ]] && read -r -p "Enter custom Plan model: " CHOICE
  PLAN_MODEL="$CHOICE"
fi

export DEFAULT_MODEL PLAN_MODEL

python3 - "$OPEN_CODE_CFG" << 'PYEOF'
import json
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])

try:
    config = json.loads(path.read_text())
except Exception:
    config = {}

config["$schema"] = "https://opencode.ai/config.json"
config["model"] = os.environ.get("DEFAULT_MODEL", "deepseek/deepseek-v4-flash")

provider = config.setdefault("provider", {})
provider["deepseek"] = {
    "npm": "@ai-sdk/deepseek",
    "options": {"apiKey": "{env:DEEPSEEK_API_KEY}"},
}
provider["openai"] = {
    "npm": "@ai-sdk/openai",
    "options": {"apiKey": "{env:OPENAI_API_KEY}"},
}

agent = config.setdefault("agent", {})
plan = agent.setdefault("plan", {})
plan["model"] = os.environ.get("PLAN_MODEL", "openai/gpt-5.5")
options = plan.setdefault("options", {})
options["reasoningEffort"] = "xhigh"

permission = config.setdefault("permission", {})
permission["edit"] = "ask"
permission["bash"] = "ask"
permission["external_directory"] = "ask"

path.write_text(json.dumps(config, indent=2) + "\n")
PYEOF

log_info "opencode defaults written to $OPEN_CODE_CFG"

if command -v whiptail &>/dev/null; then
  SCENARIO_CHOICES=$(whiptail --title "opencode MCP Toolkits" --checklist \
    "Select toolkits to configure (SPACE to toggle):" 20 65 8 \
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
  log_warn "whiptail not found — skipping opencode MCP toolkit selection"
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

  python3 - "$OPEN_CODE_CFG" "$NEED_SERVERS" \
      "$BRAVE_API_KEY" "$GITHUB_TOKEN" "$POSTGRES_DSN" "$SQLITE_PATH" << 'PYEOF'
import json
import pathlib
import sys

path      = pathlib.Path(sys.argv[1])
servers   = sys.argv[2].split()
brave_key = sys.argv[3]
gh_token  = sys.argv[4]
pg_dsn    = sys.argv[5]
sqlite_p  = sys.argv[6]

try:
    config = json.loads(path.read_text())
except Exception:
    config = {}

mcp = config.setdefault("mcp", {})
managed = {
    "context7", "excalidraw", "puppeteer", "github", "brave-search",
    "postgres", "sqlite", "claude-in-chrome",
}
for name in managed:
    mcp.pop(name, None)

def local(command, environment=None):
    entry = {"type": "local", "command": command, "enabled": True}
    if environment:
        entry["environment"] = environment
    return entry

if "context7" in servers:
    mcp["context7"] = local(["npx", "-y", "@upstash/context7-mcp@latest"])
if "excalidraw" in servers:
    mcp["excalidraw"] = local(["npx", "-y", "@anthropic-ai/mcp-server-excalidraw"])
if "puppeteer" in servers:
    mcp["puppeteer"] = local(["npx", "-y", "@modelcontextprotocol/server-puppeteer"])
if "github" in servers and gh_token:
    mcp["github"] = local(["npx", "-y", "@modelcontextprotocol/server-github"], {"GITHUB_PERSONAL_ACCESS_TOKEN": gh_token})
if "brave-search" in servers and brave_key:
    mcp["brave-search"] = local(["npx", "-y", "@modelcontextprotocol/server-brave-search"], {"BRAVE_API_KEY": brave_key})
if "postgres" in servers and pg_dsn:
    mcp["postgres"] = local(["npx", "-y", "@modelcontextprotocol/server-postgres", pg_dsn])
if "sqlite" in servers:
    mcp["sqlite"] = local(["npx", "-y", "@modelcontextprotocol/server-sqlite", "--db-path", sqlite_p])
if "dev-chrome" in servers:
    mcp["claude-in-chrome"] = local(["npx", "-y", "@anthropic-ai/claude-in-chrome-mcp"])

path.write_text(json.dumps(config, indent=2) + "\n")
PYEOF

  log_info "opencode MCP toolkit servers written to $OPEN_CODE_CFG"
fi

log_info "opencode: done"
