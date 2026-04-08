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

log_info "codex-cc: done"
