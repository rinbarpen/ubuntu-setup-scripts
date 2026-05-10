#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"
source "${SCRIPT_DIR}/../lib/api.sh"

need_cmd git

ARIS_REPO="https://github.com/wanshuiyin/Auto-claude-code-research-in-sleep.git"
ARIS_DIR="${HOME}/.local/share/aris"
SKILLS_TARGET="${HOME}/.claude/skills"
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
CODEX_CFG="${HOME}/.codex/config.toml"

log_info "Auto-Research-In-Sleep (ARIS) installation"

# Clone or update ARIS repository
if [[ -d "${ARIS_DIR}/.git" ]]; then
  log_info "Updating ARIS repository..."
  git -C "$ARIS_DIR" pull --ff-only || log_warn "git pull failed — continuing with existing"
else
  log_info "Cloning ARIS repository..."
  mkdir -p "$(dirname "$ARIS_DIR")"
  git clone "$ARIS_REPO" "$ARIS_DIR" || { log_err "Failed to clone ARIS"; exit 1; }
fi

# Install ARIS skills (symlink or copy)
log_info "Installing ARIS skills..."
mkdir -p "$SKILLS_TARGET"

if [[ -f "${ARIS_DIR}/tools/install_aris.sh" ]]; then
  log_info "Running ARIS install script..."
  bash "${ARIS_DIR}/tools/install_aris.sh" || log_warn "install_aris.sh failed — falling back to copy"
  _aris_method="install_aris.sh"
else
  # Fallback: copy skills directly
  if [[ -d "${ARIS_DIR}/skills" ]]; then
    _existing_count=$(find "$SKILLS_TARGET" -maxdepth 1 -type d | wc -l)
    cp -r "${ARIS_DIR}/skills/"* "$SKILLS_TARGET/" 2>/dev/null || true
    _new_count=$(find "$SKILLS_TARGET" -maxdepth 1 -type d | wc -l)
    log_info "Copied skills to ${SKILLS_TARGET} ($((_new_count - _existing_count)) new directories)"
    _aris_method="copy"
  else
    log_warn "No skills/ directory found in ARIS repo"
    _aris_method="none"
  fi
fi

# Set skillsDirectory in Claude Code settings
if [[ -f "$CLAUDE_SETTINGS" ]]; then
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
fi

# Codex MCP server for review skill (optional)
if command -v codex &>/dev/null; then
  if confirm "Add codex MCP server (required for ARIS review skill)?"; then
    mkdir -p "$(dirname "$CODEX_CFG")"
    python3 - "$CODEX_CFG" << 'PYEOF'
import json, pathlib, re, sys

path = pathlib.Path(sys.argv[1])
def q(v):
    return json.dumps(v)

lines = path.read_text().splitlines(True) if path.exists() else []
table_re = re.compile(r'^\s*\[([^\]]+)\]\s*$')
out = []
skip = False
for line in lines:
    match = table_re.match(line)
    if match:
        table = match.group(1)
        skip = table in {"mcp_servers.codex"}
    if not skip:
        out.append(line)

while out and not out[-1].strip():
    out.pop()

out.append("\n")
out.append("[mcp_servers.codex]\n")
out.append(f"command = {q('codex')}\n")
out.append("args = [" + ", ".join(q(a) for a in ["mcp-server"]) + "]\n")

path.write_text("".join(out))
PYEOF
    log_info "Codex MCP server added to ${CODEX_CFG}"
  fi
fi

# Register ARIS scenario MCP servers in Claude Code settings
log_info "Configuring ARIS-required MCP servers..."
BRAVE_API_KEY=$(api_key_get "BRAVE_API_KEY" "BRAVE_API_KEY (leave empty to skip brave-search)" true)
export BRAVE_API_KEY

if [[ -f "$CLAUDE_SETTINGS" ]]; then
  python3 - "$CLAUDE_SETTINGS" << 'PYEOF'
import json, os, pathlib, sys

path = pathlib.Path(sys.argv[1])
try:
    s = json.loads(path.read_text())
except Exception:
    s = {}

BRAVE_API_KEY = os.environ.get("BRAVE_API_KEY", "")
mcp = s.setdefault("mcpServers", {})

# brave-search (if key provided)
if BRAVE_API_KEY and "brave-search" not in mcp:
    mcp["brave-search"] = {
        "command": "npx",
        "args": ["-y", "@anthropic-ai/mcp-server-brave-search"],
        "env": {"BRAVE_API_KEY": BRAVE_API_KEY},
    }

# context7 (if not already configured)
if "context7" not in mcp:
    mcp["context7"] = {
        "command": "npx",
        "args": ["-y", "context7"],
    }

# puppeteer (if not already configured)
if "puppeteer" not in mcp:
    mcp["puppeteer"] = {
        "command": "npx",
        "args": ["-y", "@anthropic-ai/mcp-server-puppeteer"],
    }

path.write_text(json.dumps(s, indent=2) + "\n")
PYEOF
  log_info "ARIS MCP servers written to ${CLAUDE_SETTINGS}"
fi

# .env setup
if [[ -f "${ARIS_DIR}/.env.example" ]] && [[ ! -f "${ARIS_DIR}/.env" ]]; then
  if confirm "Create .env from .env.example for ARIS?"; then
    cp "${ARIS_DIR}/.env.example" "${ARIS_DIR}/.env"
    log_info "Created ${ARIS_DIR}/.env — edit it to add your API keys"
  fi
fi

# Print next steps
echo ""
log_info "ARIS setup complete (method: ${_aris_method})"
echo ""
echo "ARIS repository: ${ARIS_DIR}"
echo "Skills installed: ${SKILLS_TARGET}"
echo ""
echo "Next steps:"
echo "1) Edit ${ARIS_DIR}/.env to add your API keys (if created)"
echo "2) Restart Claude Code, then run ARIS workflows:"
echo "   /idea-discovery \"research topic\"    — Literature survey + idea generation"
echo "   /auto-review-loop \"topic\"           — Iterative paper improvement"
echo "   /research-pipeline \"topic\"          — Full pipeline end-to-end"
echo "   /research-wiki init                 — Enable persistent research memory"
echo ""

log_info "aris: done"
