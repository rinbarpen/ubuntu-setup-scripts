#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

need_cmd npm

CODEX_CFG="$HOME/.codex/config.toml"
CODEX_LEGACY_CFG="$HOME/.codex/config.yaml"

# Install codex CLI
log_info "Installing codex CLI..."
npm install -g @openai/codex

if [[ -f "$CODEX_LEGACY_CFG" ]]; then
  log_warn "Found legacy Codex config at $CODEX_LEGACY_CFG; current Codex CLI uses $CODEX_CFG. Leaving legacy file unchanged."
fi

mkdir -p "$(dirname "$CODEX_CFG")"

# Codex model selection
CODEX_MODEL=""
if command -v whiptail &>/dev/null; then
  CHOICE=$(whiptail --title "Codex Model" --menu "Select default model for Codex (or skip to use plan mode):" 20 75 10 \
      "do-not-set"    "Do not set model (use plan mode for reasoning)" \
      "deepseek-v4-pro" "DeepSeek V4 Pro" \
      "deepseek-v4-flash" "DeepSeek V4 Flash (for plan mode)" \
      "custom" "Custom model ID" \
      3>&1 1>&2 2>&3) || CHOICE="do-not-set"

  if [[ "$CHOICE" == "custom" ]]; then
    read -r -p "Enter model ID: " CODEX_MODEL
  elif [[ "$CHOICE" != "do-not-set" ]]; then
    CODEX_MODEL="$CHOICE"
  fi
fi
export CODEX_MODEL

# Write codex defaults
python3 - "$CODEX_CFG" << 'PYEOF'
import json
import pathlib
import re
import sys
import os

path = pathlib.Path(sys.argv[1])
managed = {
    "model_reasoning_effort": "medium",
    "plan_mode_reasoning_effort": "xhigh",
    "approval_policy": "on-request",
    "sandbox_mode": "workspace-write",
}

# Only add model if user selected one
codex_model = os.environ.get("CODEX_MODEL")
if codex_model:
    managed["model"] = codex_model
    # DeepSeek models need custom base URL (OpenAI format)
    if "deepseek" in codex_model.lower():
        managed["openai_base_url"] = "https://api.deepseek.com"


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
if command -v whiptail &>/dev/null; then
  SCENARIO_CHOICES=$(whiptail --title "MCP Toolkits (codex)" --checklist \
      "Select toolkits to configure for codex (SPACE to toggle):" 20 65 8 \
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
  log_warn "whiptail not found — skipping MCP toolkit selection for codex"
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

log_info "codex: done"
