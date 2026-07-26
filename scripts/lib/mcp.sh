#!/usr/bin/env bash
# mcp.sh — Centralized MCP (Model Context Protocol) server management
#
# This library extracts the scenario→server→credential→config-write pattern
# that is duplicated across opencode.sh, codex.sh, claude-code.sh, and
# hermes-agent.sh. It provides:
#
#   mcp_select_scenarios <title_label>
#       Shows a whiptail checklist of 11 MCP scenarios.  Returns a
#       space-separated list of selected scenario names on stdout.
#
#   mcp_collect_credentials <scenario_list>
#       Prompts (via api.sh) for BRAVE_API_KEY, GITHUB_TOKEN,
#       POSTGRES_DSN, and SQLITE_PATH — only for servers required by
#       the given scenarios.  Returns a pipe-separated credential string
#       on stdout:  <brave_key>|<github_token>|<postgres_dsn>|<sqlite_path>
#
#   mcp_write_json <config_path> <mcp_key> <scenarios> <cred_string>
#       Writes MCP server entries into a JSON config file (used by
#       claude-code, opencode, pi, omp).
#
#   mcp_write_toml <config_path> <scenarios> <cred_string>
#       Writes MCP server entries into a TOML config file (used by codex).
#
# Dependencies: utils.sh, api.sh (must be sourced before this file)
# ---------------------------------------------------------------------------
# Ensure this file is only sourced once
[[ -n "${_MCP_SH_LOADED:-}" ]] && return 0
_MCP_SH_LOADED=1

# ---------------------------------------------------------------------------
# MCP scenario → required servers mapping
# ---------------------------------------------------------------------------
declare -A MCP_SCENARIO_SERVERS
MCP_SCENARIO_SERVERS[recommended]="context7 brave-search excalidraw puppeteer"
MCP_SCENARIO_SERVERS[frontend]="context7 excalidraw puppeteer dev-chrome"
MCP_SCENARIO_SERVERS[backend]="context7 github postgres sqlite"
MCP_SCENARIO_SERVERS[testing]="context7 github puppeteer dev-chrome"
MCP_SCENARIO_SERVERS[research]="brave-search puppeteer context7 sqlite"
MCP_SCENARIO_SERVERS[auto-research-in-sleeping]="brave-search puppeteer context7 sqlite"
MCP_SCENARIO_SERVERS[analyst]="brave-search context7 postgres sqlite"
MCP_SCENARIO_SERVERS[stock]="brave-search context7"
MCP_SCENARIO_SERVERS[marketing]="brave-search excalidraw"
MCP_SCENARIO_SERVERS[daily]="brave-search context7"
MCP_SCENARIO_SERVERS[chat]="brave-search context7"

# Server definition: command,args (comma-separated) | optional_env_var_name
declare -A MCP_SERVER_DEFS
MCP_SERVER_DEFS[context7]="npx,-y,@upstash/context7-mcp@latest|"
MCP_SERVER_DEFS[excalidraw]="npx,-y,@anthropic-ai/mcp-server-excalidraw|"
MCP_SERVER_DEFS[puppeteer]="npx,-y,@modelcontextprotocol/server-puppeteer|"
MCP_SERVER_DEFS[github]="npx,-y,@modelcontextprotocol/server-github|GITHUB_PERSONAL_ACCESS_TOKEN"
MCP_SERVER_DEFS[brave-search]="npx,-y,@modelcontextprotocol/server-brave-search|BRAVE_API_KEY"
MCP_SERVER_DEFS[postgres]="npx,-y,@modelcontextprotocol/server-postgres|"
MCP_SERVER_DEFS[sqlite]="npx,-y,@modelcontextprotocol/server-sqlite|"
MCP_SERVER_DEFS[dev-chrome]="npx,-y,@anthropic-ai/claude-in-chrome-mcp|"

# ---------------------------------------------------------------------------
# mcp_select_scenarios <title_label>
# ---------------------------------------------------------------------------
mcp_select_scenarios() {
  local title="${1:-MCP Toolkits}"

  if ! command -v whiptail &>/dev/null; then
    log_warn "whiptail not found — skipping MCP scenario selection"
    echo ""
    return 0
  fi

  local choices
  choices=$(whiptail --title "$title" --checklist \
    "Select toolkits to configure (SPACE to toggle):" 20 65 11 \
    "recommended" "推荐: context7, brave-search, excalidraw, puppeteer" ON \
    "frontend"   "前端开发: context7, excalidraw, puppeteer"   OFF \
    "backend"    "后端开发: context7, github, postgres, sqlite" OFF \
    "testing"    "测试:     context7, github, puppeteer"       OFF \
    "research"   "科研/ARIS: brave-search, puppeteer, context7, sqlite" ON \
    "auto-research-in-sleeping" "ARIS 自动研究: brave-search, puppeteer, context7, sqlite" OFF \
    "analyst"    "分析师:   brave-search, context7, postgres"  OFF \
    "stock"      "股票:     brave-search, context7"            OFF \
    "marketing"  "市场:     brave-search, excalidraw"          OFF \
    "daily"      "日常:     brave-search, context7"            ON \
    "chat"       "对话:     brave-search, context7"            ON \
    3>&1 1>&2 2>&3) || choices=""

  echo "$choices" | tr -d '"'
}

# ---------------------------------------------------------------------------
# mcp_collect_credentials <scenario_list>
#
# Returns a pipe-separated string:
#   <brave_key>|<github_token>|<postgres_dsn>|<sqlite_path>
# ---------------------------------------------------------------------------
mcp_collect_credentials() {
  local scenarios="$1"
  local -A NEED_MCP
  local scenario

  for scenario in $scenarios; do
    local svr_list="${MCP_SCENARIO_SERVERS[$scenario]:-}"
    if [[ -z "$svr_list" ]]; then
      log_warn "Unknown MCP scenario: $scenario"
      continue
    fi
    for svr in $svr_list; do
      NEED_MCP[$svr]=1
    done
  done

  # Collect API keys (only for servers that are needed)
  local brave_key=""
  if [[ -n "${NEED_MCP[brave-search]:-}" ]]; then
    brave_key=$(api_key_get "BRAVE_API_KEY" "BRAVE_API_KEY (leave empty to skip brave-search)" true)
    if [[ -z "$brave_key" ]]; then
      log_warn "No BRAVE_API_KEY — skipping brave-search"
      unset "NEED_MCP[brave-search]"
    fi
  fi

  local github_token=""
  if [[ -n "${NEED_MCP[github]:-}" ]]; then
    github_token=$(api_key_get "GITHUB_TOKEN" "GitHub Personal Access Token (leave empty to skip github)" true)
    if [[ -z "$github_token" ]]; then
      log_warn "No GitHub token — skipping github"
      unset "NEED_MCP[github]"
    fi
  fi

  local postgres_dsn=""
  if [[ -n "${NEED_MCP[postgres]:-}" ]]; then
    postgres_dsn=$(api_key_get "POSTGRES_DSN" "Postgres connection string (leave empty to skip)" false)
    if [[ -z "$postgres_dsn" ]]; then
      log_warn "No Postgres DSN — skipping postgres"
      unset "NEED_MCP[postgres]"
    fi
  fi

  local sqlite_path="$HOME/data.db"
  if [[ -n "${NEED_MCP[sqlite]:-}" ]]; then
    local _input
    read -r -p "SQLite DB path [${sqlite_path}]: " _input
    [[ -n "$_input" ]] && sqlite_path="$_input"
  fi

  # Build the remaining servers list
  local servers="${!NEED_MCP[*]}"

  # Return: servers|brave_key|github_token|postgres_dsn|sqlite_path
  echo "${servers}|${brave_key}|${github_token}|${postgres_dsn}|${sqlite_path}"
}

# ---------------------------------------------------------------------------
# mcp_write_json <config_path> <mcp_key> <scenarios> <cred_string>
#
# cred_string format: <servers>|<brave_key>|<github_token>|<postgres_dsn>|<sqlite_path>
# ---------------------------------------------------------------------------
mcp_write_json() {
  local config_path="$1"
  local mcp_key="$2"
  local scenarios="$3"
  local cred_string="$4"

  IFS='|' read -r _srv _brave _github _pg _sqlite <<< "$cred_string"

  python3 - "$config_path" "$mcp_key" "$_srv" "$_brave" "$_github" "$_pg" "$_sqlite" << 'PYEOF'
import json, sys

path     = sys.argv[1]
mcp_key  = sys.argv[2]
servers  = sys.argv[3].split()
brave_key = sys.argv[4]
gh_token  = sys.argv[5]
pg_dsn    = sys.argv[6]
sqlite_p  = sys.argv[7]

try:
    with open(path) as f:
        s = json.load(f)
except Exception:
    s = {}

mcp = s.setdefault(mcp_key, {})

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
}

# ---------------------------------------------------------------------------
# mcp_write_json_local <config_path> <mcp_key> <scenarios> <cred_string>
#
# Like mcp_write_json but uses opencode's "local" type format:
#   {"type": "local", "command": [...], "enabled": true}
# ---------------------------------------------------------------------------
mcp_write_json_local() {
  local config_path="$1"
  local mcp_key="$2"
  local scenarios="$3"
  local cred_string="$4"

  IFS='|' read -r _srv _brave _github _pg _sqlite <<< "$cred_string"

  python3 - "$config_path" "$mcp_key" "$_srv" "$_brave" "$_github" "$_pg" "$_sqlite" << 'PYEOF'
import json, sys

path     = sys.argv[1]
mcp_key  = sys.argv[2]
servers  = sys.argv[3].split()
brave_key = sys.argv[4]
gh_token  = sys.argv[5]
pg_dsn    = sys.argv[6]
sqlite_p  = sys.argv[7]

try:
    config = json.loads(open(path).read())
except Exception:
    config = {}

mcp = config.setdefault(mcp_key, {})

# Remove previously managed servers
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

if 'context7' in servers:
    mcp['context7'] = local(["npx", "-y", "@upstash/context7-mcp@latest"])
if 'excalidraw' in servers:
    mcp['excalidraw'] = local(["npx", "-y", "@anthropic-ai/mcp-server-excalidraw"])
if 'puppeteer' in servers:
    mcp['puppeteer'] = local(["npx", "-y", "@modelcontextprotocol/server-puppeteer"])
if 'github' in servers and gh_token:
    mcp['github'] = local(["npx", "-y", "@modelcontextprotocol/server-github"], {"GITHUB_PERSONAL_ACCESS_TOKEN": gh_token})
if 'brave-search' in servers and brave_key:
    mcp['brave-search'] = local(["npx", "-y", "@modelcontextprotocol/server-brave-search"], {"BRAVE_API_KEY": brave_key})
if 'postgres' in servers and pg_dsn:
    mcp['postgres'] = local(["npx", "-y", "@modelcontextprotocol/server-postgres", pg_dsn])
if 'sqlite' in servers:
    mcp['sqlite'] = local(["npx", "-y", "@modelcontextprotocol/server-sqlite", "--db-path", sqlite_p])
if 'dev-chrome' in servers:
    mcp['claude-in-chrome'] = local(["npx", "-y", "@anthropic-ai/claude-in-chrome-mcp"])

with open(path, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')
PYEOF
}

# ---------------------------------------------------------------------------
# mcp_write_toml <config_path> <scenarios> <cred_string>
#
# Writes MCP server entries into a TOML config file (codex format).
# ---------------------------------------------------------------------------
mcp_write_toml() {
  local config_path="$1"
  local scenarios="$2"
  local cred_string="$3"

  IFS='|' read -r _srv _brave _github _pg _sqlite <<< "$cred_string"

  python3 - "$config_path" "$_srv" "$_brave" "$_github" "$_pg" "$_sqlite" << 'PYEOF'
import re, sys

path      = sys.argv[1]
servers   = sys.argv[2].split()
brave_key = sys.argv[3]
gh_token  = sys.argv[4]
pg_dsn    = sys.argv[5]
sqlite_p  = sys.argv[6]

try:
    with open(path) as f:
        content = f.read()
except Exception:
    content = ""

# Remove previously managed MCP server sections
_managed = [
    "context7", "excalidraw", "puppeteer", "github",
    "brave-search", "postgres", "sqlite", "claude-in-chrome",
]
for name in _managed:
    content = re.sub(
        r'\n?\[mcp_servers\.' + re.escape(name) + r'\][^\[]*',
        '', content, flags=re.DOTALL
    )

lines = content.rstrip('\n').split('\n') if content.strip() else []

def add_server(name, command, args_str, env_str=""):
    lines.append(f"\n[mcp_servers.{name}]")
    lines.append(f'command = "{command}"')
    if args_str:
        lines.append(f'args = {args_str}')
    if env_str:
        lines.append(f'[mcp_servers.{name}.env]')
        lines.append(env_str)

if 'context7' in servers:
    add_server("context7", "npx", '["-y", "@upstash/context7-mcp@latest"]')
if 'excalidraw' in servers:
    add_server("excalidraw", "npx", '["-y", "@anthropic-ai/mcp-server-excalidraw"]')
if 'puppeteer' in servers:
    add_server("puppeteer", "npx", '["-y", "@modelcontextprotocol/server-puppeteer"]')
if 'github' in servers and gh_token:
    add_server("github", "npx", '["-y", "@modelcontextprotocol/server-github"]',
               f'GITHUB_PERSONAL_ACCESS_TOKEN = "{gh_token}"')
if 'brave-search' in servers and brave_key:
    add_server("brave-search", "npx", '["-y", "@modelcontextprotocol/server-brave-search"]',
               f'BRAVE_API_KEY = "{brave_key}"')
if 'postgres' in servers and pg_dsn:
    add_server("postgres", "npx", f'["-y", "@modelcontextprotocol/server-postgres", "{pg_dsn}"]')
if 'sqlite' in servers:
    add_server("sqlite", "npx", f'["-y", "@modelcontextprotocol/server-sqlite", "--db-path", "{sqlite_p}"]')
if 'dev-chrome' in servers:
    add_server("dev-chrome", "npx", '["-y", "@anthropic-ai/claude-in-chrome-mcp"]')

with open(path, 'w') as f:
    f.write('\n'.join(lines).strip() + '\n')
PYEOF
}
