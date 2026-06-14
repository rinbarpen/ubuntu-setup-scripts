#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"
source "${SCRIPT_DIR}/../lib/api.sh"

need_cmd npm
need_cmd python3

HERMES_CFG="$HOME/.hermes/config.yaml"

# Install Hermes Agent (npm bridge) — skip if already installed
if command -v hermes &>/dev/null; then
  log_info "Hermes Agent already installed ($(command -v hermes)), skipping npm install"
else
  log_info "Installing Hermes Agent..."
  npm install -g hermes-agent
fi

mkdir -p "$(dirname "$HERMES_CFG")"

# ── Provider + Model selection ──────────────────────────────────────────────

HERMES_PROVIDER="deepseek"
HERMES_MODEL="deepseek-v4-flash"
HERMES_BASE_URL="https://api.deepseek.com/v1"

# Read existing values from config
if [[ -f "$HERMES_CFG" ]]; then
  eval "$(
    python3 - "$HERMES_CFG" << 'PYEOF' 2>/dev/null || echo ""
import pathlib, sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
lines = text.splitlines()

p = ""
m = ""
b = ""
in_model = False
for line in lines:
    stripped = line.rstrip()
    if stripped == "model:":
        in_model = True
        continue
    if in_model:
        if stripped and not stripped.startswith(" "):
            in_model = False
            continue
        if stripped.startswith("provider:"):
            p = stripped.split(":", 1)[1].strip()
        elif stripped.startswith("default:"):
            m = stripped.split(":", 1)[1].strip()
        elif stripped.startswith("base_url:"):
            b = stripped.split(":", 1)[1].strip()

print(f"HERMES_PROVIDER={p!r}")
print(f"HERMES_MODEL={m!r}")
print(f"HERMES_BASE_URL={b!r}")
PYEOF
  )"
fi

if command -v whiptail &>/dev/null; then
  _prov_choice=$(whiptail --title "Hermes Provider" --menu \
      "Select inference provider:" 18 60 8 \
      "deepseek"   "DeepSeek (api.deepseek.com)" \
      "openai"     "OpenAI (api.openai.com)" \
      "openrouter" "OpenRouter (multi-provider proxy)" \
      "anthropic"  "Anthropic (api.anthropic.com)" \
      "custom"     "Custom provider URL" \
      3>&1 1>&2 2>&3) || _prov_choice="$HERMES_PROVIDER"

  case "$_prov_choice" in
    deepseek)
      HERMES_PROVIDER="deepseek"
      HERMES_BASE_URL="https://api.deepseek.com/v1"
      ;;
    openai)
      HERMES_PROVIDER="openai"
      HERMES_BASE_URL="https://api.openai.com/v1"
      ;;
    openrouter)
      HERMES_PROVIDER="openrouter"
      HERMES_BASE_URL="https://openrouter.ai/api/v1"
      ;;
    anthropic)
      HERMES_PROVIDER="anthropic"
      HERMES_BASE_URL="https://api.anthropic.com/v1"
      ;;
    custom)
      read -r -p "Provider name (e.g. myproxy): " HERMES_PROVIDER
      read -r -p "API base URL: " HERMES_BASE_URL
      ;;
  esac

  # Model selection — contextual menu per provider
  _model_choice=""
  case "$HERMES_PROVIDER" in
    deepseek)
      _model_choice=$(whiptail --title "Hermes Model" --menu \
          "Select default model for DeepSeek:" 18 65 8 \
          "deepseek-v4-flash" "DeepSeek V4 Flash (fast & cheap)" \
          "deepseek-v4-pro"   "DeepSeek V4 Pro (enhanced capability)" \
          "deepseek-chat"     "DeepSeek V3 Chat" \
          "custom"            "Custom model name" \
          3>&1 1>&2 2>&3) || _model_choice="$HERMES_MODEL"
      ;;
    openai)
      _model_choice=$(whiptail --title "Hermes Model" --menu \
          "Select default model for OpenAI:" 18 65 8 \
          "gpt-5.5"  "OpenAI GPT-5.5" \
          "gpt-4o"   "OpenAI GPT-4o" \
          "o4-mini"  "OpenAI o4-mini" \
          "custom"   "Custom model name" \
          3>&1 1>&2 2>&3) || _model_choice="$HERMES_MODEL"
      ;;
    openrouter)
      read -r -p "OpenRouter model (e.g. anthropic/claude-sonnet-4) [${HERMES_MODEL}]: " _model_choice
      _model_choice="${_model_choice:-$HERMES_MODEL}"
      ;;
    anthropic)
      _model_choice=$(whiptail --title "Hermes Model" --menu \
          "Select default model for Anthropic:" 18 65 8 \
          "claude-sonnet-4-20250514" "Claude Sonnet 4" \
          "claude-opus-4-20250514"   "Claude Opus 4" \
          "claude-haiku-4-20250514"  "Claude Haiku 4" \
          "custom"                   "Custom model name" \
          3>&1 1>&2 2>&3) || _model_choice="$HERMES_MODEL"
      ;;
    *)
      read -r -p "Model name [${HERMES_MODEL}]: " _model_choice
      _model_choice="${_model_choice:-$HERMES_MODEL}"
      ;;
  esac

  if [[ "$_model_choice" == "custom" ]]; then
    read -r -p "Enter model name: " _model_choice
  fi
  [[ -n "$_model_choice" ]] && HERMES_MODEL="$_model_choice"

  # Prompt for API key
  echo ""
  case "$HERMES_PROVIDER" in
    deepseek)   api_key_get "DEEPSEEK_API_KEY" "DEEPSEEK_API_KEY" true ;;
    openai)     api_key_get "OPENAI_API_KEY" "OPENAI_API_KEY" true ;;
    openrouter) api_key_get "OPENROUTER_API_KEY" "OPENROUTER_API_KEY" true ;;
    anthropic)  api_key_get "ANTHROPIC_API_KEY" "ANTHROPIC_API_KEY" true ;;
  esac
fi

export HERMES_PROVIDER HERMES_MODEL HERMES_BASE_URL

# ── Write model section to config ───────────────────────────────────────────

python3 - "$HERMES_CFG" << 'PYEOF'
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])

provider = os.environ.get("HERMES_PROVIDER", "")
model    = os.environ.get("HERMES_MODEL", "")
base_url = os.environ.get("HERMES_BASE_URL", "")

# Read existing, strip model section
existing_lines = path.read_text().splitlines(True) if path.exists() else []
managed = {"model"}

result = []
i = 0
skip = False
while i < len(existing_lines):
    line = existing_lines[i]
    stripped = line.rstrip()

    if stripped == "model:":
        skip = True
        i += 1
        continue
    if skip:
        if stripped == "" or not stripped.startswith(" "):
            skip = False
            result.append(line)
            i += 1
            continue
        i += 1
        continue
    result.append(line)
    i += 1

# Clean trailing blank lines
while result and not result[-1].strip():
    result.pop()

# Append model section
result.append("\n")
result.append("model:\n")
result.append(f"  default: {model}\n")
if provider:
    result.append(f"  provider: {provider}\n")
if base_url:
    result.append(f"  base_url: {base_url}\n")

output = "".join(result)
if not output.endswith("\n"):
    output += "\n"
path.write_text(output)
PYEOF

log_info "Hermes model config written to $HERMES_CFG"

# ── MCP Toolkits ── scenario-based selection ────────────────────────────────

if [[ -f "$HERMES_CFG" ]]; then
  _existing_mcp=$(python3 - "
import pathlib
text = pathlib.Path('$HERMES_CFG').read_text()
lines = text.splitlines()
in_mcp = False
for i, line in enumerate(lines):
    if line.rstrip() == 'mcp_servers:':
        in_mcp = True
        continue
    if in_mcp:
        s = line.rstrip()
        if s and not s.startswith(' '):
            break
        if s.startswith('  ') and s.endswith(':') and not s.startswith('    '):
            print(s.split(':')[0].strip())
" 2>/dev/null)
  if [[ -n "$_existing_mcp" ]]; then
    log_info "Currently configured MCP servers:"
    echo "$_existing_mcp" | while IFS= read -r _srv; do echo "  - $_srv"; done
  fi
fi

SCENARIOS=""
if command -v whiptail &>/dev/null; then
  SCENARIO_CHOICES=$(whiptail --title "MCP Toolkits (Hermes)" --checklist \
      "Select toolkits to configure (SPACE to toggle):" 20 65 11 \
      "recommended" "推荐: context7, brave-search, excalidraw, puppeteer" ON  \
      "frontend"   "前端开发: context7, excalidraw, puppeteer"   OFF \
      "backend"    "后端开发: context7, github, postgres, sqlite" OFF \
      "testing"    "测试:     context7, github, puppeteer"       OFF \
      "research"   "科研:    brave-search, puppeteer, context7, sqlite" ON  \
      "analyst"    "分析师:   brave-search, context7, postgres"  OFF \
      "stock"      "股票:     brave-search, context7"            OFF \
      "marketing"  "市场:     brave-search, excalidraw"          OFF \
      "daily"      "日常:     brave-search, context7"            ON  \
      "chat"       "对话:     brave-search, context7"            ON  \
      3>&1 1>&2 2>&3) || SCENARIO_CHOICES=""
  SCENARIOS=$(echo "$SCENARIO_CHOICES" | tr -d '"')
else
  log_warn "whiptail not found — skipping MCP toolkit selection for Hermes"
fi

if [[ -n "$SCENARIOS" ]]; then
  declare -A NEED_MCP
  for scenario in $SCENARIOS; do
    case "$scenario" in
      recommended) NEED_MCP[context7]=1; NEED_MCP[brave-search]=1; NEED_MCP[excalidraw]=1; NEED_MCP[puppeteer]=1 ;;
      frontend)  NEED_MCP[context7]=1; NEED_MCP[excalidraw]=1; NEED_MCP[puppeteer]=1; NEED_MCP[dev-chrome]=1 ;;
      backend)   NEED_MCP[context7]=1; NEED_MCP[github]=1; NEED_MCP[postgres]=1; NEED_MCP[sqlite]=1 ;;
      testing)   NEED_MCP[context7]=1; NEED_MCP[github]=1; NEED_MCP[puppeteer]=1; NEED_MCP[dev-chrome]=1 ;;
      research|auto-research-in-sleeping) NEED_MCP[brave-search]=1; NEED_MCP[puppeteer]=1; NEED_MCP[context7]=1; NEED_MCP[sqlite]=1 ;;
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

  python3 - "$HERMES_CFG" "$NEED_SERVERS" \
      "$BRAVE_API_KEY" "$GITHUB_TOKEN" "$POSTGRES_DSN" "$SQLITE_PATH" << 'PYEOF'
import os
import pathlib
import sys

def q(v):
    """YAML-safe string quoting — single-quote if the value contains
    characters that would confuse a plain scalar parser."""
    if not isinstance(v, str):
        return str(v)
    if any(c in v for c in ':#{}[]&*!|>?'"`%@') or ' ' in v:
        return "'" + v.replace("'", "''") + "'"
    return v

def yaml_list(items):
    return "[" + ", ".join(q(i) for i in items) + "]"

path      = pathlib.Path(sys.argv[1])
servers   = sys.argv[2].split()
brave_key = sys.argv[3]
gh_token  = sys.argv[4]
pg_dsn    = sys.argv[5]
sqlite_p  = sys.argv[6]

managed_names = {
    "context7", "excalidraw", "puppeteer", "github", "brave-search",
    "postgres", "sqlite", "claude-in-chrome", "dev-chrome",
}

# Read existing config, remove managed MCP server entries
lines = path.read_text().splitlines(True) if path.exists() else []
in_mcp_block = False
mcp_block_start = -1

for i, line in enumerate(lines):
    s = line.rstrip()
    if s == "mcp_servers:":
        in_mcp_block = True
        mcp_block_start = i
    elif in_mcp_block:
        if s == "" or not s.startswith(" "):
            in_mcp_block = False

# Determine the range of lines to skip
skip_start = mcp_block_start if mcp_block_start >= 0 else -1
if skip_start >= 0:
    i = skip_start + 1
    while i < len(lines):
        s = lines[i].rstrip()
        if s == "" or not s.startswith(" "):
            break
        i += 1
    skip_end = i

    out = lines[:skip_start] + lines[skip_end:]
else:
    out = lines[:]

# Clean trailing blank lines
out_clean = []
for line in out:
    if out_clean or line.strip():
        out_clean.append(line)
while out_clean and not out_clean[-1].strip():
    out_clean.pop()
out = out_clean

# Write mcp_servers block
def add_server(name, command, args, env=None):
    out.append(f"  {name}:\n")
    out.append(f"    command: {q(command)}\n")
    out.append(f"    args: {yaml_list(args)}\n")
    if env:
        for key, val in env.items():
            out.append(f"    env:\n")
            out.append(f"      {key}: {q(val)}\n")

has_mcp = any(s in servers for s in managed_names)
if has_mcp:
    out.append("\n")
    out.append("mcp_servers:\n")

if "context7" in servers:
    add_server("context7", "npx", ["-y", "@upstash/context7-mcp@latest"])
if "excalidraw" in servers:
    add_server("excalidraw", "npx", ["-y", "@anthropic-ai/mcp-server-excalidraw"])
if "puppeteer" in servers:
    add_server("puppeteer", "npx", ["-y", "@modelcontextprotocol/server-puppeteer"])
if "github" in servers and gh_token:
    add_server("github", "npx", ["-y", "@modelcontextprotocol/server-github"],
               {"GITHUB_PERSONAL_ACCESS_TOKEN": gh_token})
if "brave-search" in servers and brave_key:
    add_server("brave-search", "npx", ["-y", "@modelcontextprotocol/server-brave-search"],
               {"BRAVE_API_KEY": brave_key})
if "postgres" in servers and pg_dsn:
    add_server("postgres", "npx", ["-y", "@modelcontextprotocol/server-postgres", pg_dsn])
if "sqlite" in servers:
    add_server("sqlite", "npx", ["-y", "@modelcontextprotocol/server-sqlite",
                                 "--db-path", sqlite_p])
if "dev-chrome" in servers:
    add_server("claude-in-chrome", "npx", ["-y", "@anthropic-ai/claude-in-chrome-mcp"])

path.write_text("".join(out))
PYEOF

  log_info "MCP toolkit servers written to $HERMES_CFG"
fi

# ── Display personality selection ───────────────────────────────────────────

HERMES_PERSONALITY="default"
if [[ -f "$HERMES_CFG" ]]; then
  _existing_personality=$(python3 - "
import pathlib
try:
    lines = pathlib.Path('$HERMES_CFG').read_text().splitlines()
    for i, line in enumerate(lines):
        if line.rstrip() == 'display:':
            for j in range(i+1, min(i+10, len(lines))):
                l = lines[j].rstrip()
                if l.startswith('personality:'):
                    print(l.split(':', 1)[1].strip())
except: pass
" 2>/dev/null) || _existing_personality=""
  [[ -n "$_existing_personality" ]] && HERMES_PERSONALITY="$_existing_personality"
fi

if command -v whiptail &>/dev/null; then
  _pers_choice=$(whiptail --title "Hermes Display Personality" --menu \
      "Select display personality:" 18 60 8 \
      "default"   "Standard assistant" \
      "kawaii"    "Cute and enthusiastic" \
      "technical" "Technical expert" \
      "concise"   "Brief and to the point" \
      "creative"  "Creative and innovative" \
      "teacher"   "Patient educator" \
      "skip"      "Do not change" \
      3>&1 1>&2 2>&3) || _pers_choice="skip"

  if [[ "$_pers_choice" != "skip" && -n "$_pers_choice" ]]; then
    HERMES_PERSONALITY="$_pers_choice"
    export HERMES_PERSONALITY

    python3 - "$HERMES_CFG" << 'PYEOF'
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
personality = os.environ.get("HERMES_PERSONALITY", "default")

lines = path.read_text().splitlines(True) if path.exists() else []
out = []
in_display = False
display_written = False

for line in lines:
    stripped = line.rstrip()
    if stripped == "display:":
        in_display = True
        display_written = True
        out.append(line)
        # Skip existing personality line within display block
        i = lines.index(line) + 1
        # We'll handle this by reading all lines and filtering
        continue

    if in_display:
        if stripped == "" or not stripped.startswith(" "):
            in_display = False
            out.append(line)
            continue
        if stripped.startswith("personality:"):
            continue  # skip old personality key
        out.append(line)
        continue

    out.append(line)

# Append personality if display block was not found
if not display_written:
    if out and out[-1].strip():
        out.append("\n")
    out.append("display:\n")
    out.append(f"  personality: {personality}\n")
else:
    # Find and append personality after the display: line
    # Re-process to insert personality line
    pass

path.write_text("".join(out))

# Second pass: if display block exists but personality line wasn't inserted,
# append it after the display: line
if display_written:
    lines2 = path.read_text().splitlines(True)
    result2 = []
    in_display2 = False
    personality_added = False
    for line in lines2:
        stripped = line.rstrip()
        result2.append(line)
        if stripped == "display:":
            in_display2 = True
            # Personality will be added after the next indented line or at block end
            continue
        if in_display2:
            if stripped == "" or not stripped.startswith(" "):
                # End of display block without personality — add it now
                result2.append(f"  personality: {personality}\n")
                personality_added = True
                in_display2 = False
            elif stripped.startswith("personality:"):
                # Personality already exists — don't duplicate
                personality_added = True
                in_display2 = False
    if in_display2 and not personality_added:
        result2.append(f"  personality: {personality}\n")
    path.write_text("".join(result2))

PYEOF
    log_info "Display personality set to: $HERMES_PERSONALITY"
  fi
fi

# ── Shell integration ───────────────────────────────────────────────────────

FISH_FUNC_DIR="$HOME/.config/fish/functions"
mkdir -p "$FISH_FUNC_DIR"

cat > "${FISH_FUNC_DIR}/hermes_env.fish" << 'FISHEOF'
function hermes-env
    if test -f ~/.config/rinbarpen/api-keys.env
        bass source ~/.config/rinbarpen/api-keys.env
        echo "Hermes API keys loaded from shared config"
    else
        echo "No API keys config found at ~/.config/rinbarpen/api-keys.env"
    end
end
FISHEOF

if ! grep -q "# hermes-env (added by setup)" "$HOME/.bashrc" 2>/dev/null; then
cat >> "$HOME/.bashrc" << 'BASHEOF'

# hermes-env (added by setup)
hermes-env() {
  local f="$HOME/.config/rinbarpen/api-keys.env"
  if [[ -f "$f" ]]; then
    # shellcheck source=/dev/null
    source "$f"
    echo "Hermes API keys loaded from shared config"
  else
    echo "No API keys config found"
  fi
}
BASHEOF
fi

log_info "hermes-agent: done"
