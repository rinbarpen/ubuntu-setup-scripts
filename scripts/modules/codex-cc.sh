#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

need_cmd npm

# Install CLIs
log_info "Installing codex CLI..."
npm install -g @openai/codex

log_info "Installing Claude Code..."
npm install -g @anthropic-ai/claude-code

# Full-auto permissions for Claude Code
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$CLAUDE_SETTINGS")"

if confirm "Grant Claude Code full Bash/file access (full-auto mode)?"; then
  if [[ -f "$CLAUDE_SETTINGS" ]]; then
    # Merge: preserve existing keys, overwrite permissions
    TMP=$(mktemp)
    python3 - "$CLAUDE_SETTINGS" > "$TMP" << 'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    s = json.load(f)
s['permissions'] = {
    'allow': ['Bash(*)', 'Read(*)', 'Write(*)', 'Edit(*)', 'Glob(*)', 'Grep(*)'],
    'deny': []
}
print(json.dumps(s, indent=2))
PYEOF
    mv "$TMP" "$CLAUDE_SETTINGS"
  else
    cat > "$CLAUDE_SETTINGS" << 'EOF'
{
  "permissions": {
    "allow": ["Bash(*)", "Read(*)", "Write(*)", "Edit(*)", "Glob(*)", "Grep(*)"],
    "deny": []
  }
}
EOF
  fi
  log_info "Full-auto permissions written to $CLAUDE_SETTINGS"
fi

# Provider profiles
PROFILES_DIR="$HOME/.config/cc-profiles"
mkdir -p "$PROFILES_DIR"

while confirm "Add a provider profile for codex/cc?"; do
  echo "Providers: anthropic / openai / openrouter / custom"
  read -r -p "Provider name: " PROVIDER
  read -r -s -p "API key: " API_KEY; echo ""

  case "$PROVIDER" in
    anthropic)
      cat > "${PROFILES_DIR}/${PROVIDER}.env" << EOF
export ANTHROPIC_API_KEY="${API_KEY}"
EOF
      ;;
    openai)
      cat > "${PROFILES_DIR}/${PROVIDER}.env" << EOF
export OPENAI_API_KEY="${API_KEY}"
EOF
      ;;
    openrouter)
      cat > "${PROFILES_DIR}/${PROVIDER}.env" << EOF
export OPENAI_API_KEY="${API_KEY}"
export OPENAI_BASE_URL="https://openrouter.ai/api/v1"
EOF
      ;;
    custom)
      read -r -p "API base URL: " BASE_URL
      cat > "${PROFILES_DIR}/${PROVIDER}.env" << EOF
export OPENAI_API_KEY="${API_KEY}"
export OPENAI_BASE_URL="${BASE_URL}"
EOF
      ;;
    *)
      log_warn "Unknown provider '$PROVIDER', writing as custom (OPENAI_API_KEY only)"
      cat > "${PROFILES_DIR}/${PROVIDER}.env" << EOF
export OPENAI_API_KEY="${API_KEY}"
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

# codex-auth function
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

# MCP Toolkits — scenario-based selection
if command -v whiptail &>/dev/null; then
  SCENARIO_CHOICES=$(whiptail --title "MCP Toolkits" --checklist \
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
  log_warn "whiptail not found — skipping MCP toolkit selection"
  SCENARIOS=""
fi

if [[ -n "$SCENARIOS" ]]; then
  # Compute union of required MCP servers across selected scenarios
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

  # Collect credentials only for servers that are needed
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

  # Serialize the needed servers as a space-separated string for python3
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

  # Write codex MCP config (~/.codex/config.yaml)
  CODEX_CFG="$HOME/.codex/config.yaml"
  mkdir -p "$(dirname "$CODEX_CFG")"
  python3 - "$CODEX_CFG" "$NEED_SERVERS" \
      "$BRAVE_API_KEY" "$GITHUB_TOKEN" "$POSTGRES_DSN" "$SQLITE_PATH" << 'PYEOF'
import sys, os

codex_path = sys.argv[1]
servers    = sys.argv[2].split()
brave_key  = sys.argv[3]
gh_token   = sys.argv[4]
pg_dsn     = sys.argv[5]
sqlite_p   = sys.argv[6]

lines = []
if os.path.exists(codex_path):
    with open(codex_path) as f:
        lines = f.readlines()

# Strip existing mcpServers block
out, in_block = [], False
for line in lines:
    if line.startswith('mcpServers:'):
        in_block = True; continue
    if in_block and (line.startswith(' ') or line.startswith('\t')):
        continue
    in_block = False
    out.append(line)

entries = []
if 'context7' in servers:
    entries.append('  context7:\n    command: npx\n    args: ["-y", "@upstash/context7-mcp@latest"]\n')
if 'excalidraw' in servers:
    entries.append('  excalidraw:\n    command: npx\n    args: ["-y", "@anthropic-ai/mcp-server-excalidraw"]\n')
if 'puppeteer' in servers:
    entries.append('  puppeteer:\n    command: npx\n    args: ["-y", "@modelcontextprotocol/server-puppeteer"]\n')
if 'github' in servers and gh_token:
    entries.append('  github:\n    command: npx\n    args: ["-y", "@modelcontextprotocol/server-github"]\n    env:\n      GITHUB_PERSONAL_ACCESS_TOKEN: "{}"\n'.format(gh_token))
if 'brave-search' in servers and brave_key:
    entries.append('  brave-search:\n    command: npx\n    args: ["-y", "@modelcontextprotocol/server-brave-search"]\n    env:\n      BRAVE_API_KEY: "{}"\n'.format(brave_key))
if 'postgres' in servers and pg_dsn:
    entries.append('  postgres:\n    command: npx\n    args: ["-y", "@modelcontextprotocol/server-postgres", "{}"]\n'.format(pg_dsn))
if 'sqlite' in servers:
    entries.append('  sqlite:\n    command: npx\n    args: ["-y", "@modelcontextprotocol/server-sqlite", "--db-path", "{}"]\n'.format(sqlite_p))
if 'dev-chrome' in servers:
    entries.append('  claude-in-chrome:\n    command: npx\n    args: ["-y", "@anthropic-ai/claude-in-chrome-mcp"]\n')

if entries:
    out.append('mcpServers:\n')
    out.extend(entries)

with open(codex_path, 'w') as f:
    f.writelines(out)
PYEOF

  log_info "Codex MCP config written to $CODEX_CFG"
fi

log_info "codex-cc: done"
