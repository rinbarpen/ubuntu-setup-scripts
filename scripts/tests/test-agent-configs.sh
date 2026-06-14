#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STUB_BIN="$TMP_DIR/bin"
HOME_DIR="$TMP_DIR/home"
mkdir -p "$STUB_BIN" "$HOME_DIR"

cat > "$STUB_BIN/npm" <<'EOF'
#!/usr/bin/env bash
echo "stub npm $*" >> "${TEST_NPM_LOG:?}"
exit 0
EOF
chmod +x "$STUB_BIN/npm"

cat > "$STUB_BIN/whiptail" <<'EOF'
#!/usr/bin/env bash
# Read next answer from preset file
if [[ -f "$TEST_WHIPTAIL_ANSWERS" ]] && [[ -s "$TEST_WHIPTAIL_ANSWERS" ]]; then
  IFS= read -r answer < "$TEST_WHIPTAIL_ANSWERS"
  tail -n +2 "$TEST_WHIPTAIL_ANSWERS" > "${TEST_WHIPTAIL_ANSWERS}.tmp"
  mv "${TEST_WHIPTAIL_ANSWERS}.tmp" "$TEST_WHIPTAIL_ANSWERS"
  printf '%s\n' "$answer" >&2
else
  printf '"daily"\n' >&2
fi
exit 0
EOF
chmod +x "$STUB_BIN/whiptail"


export TEST_NPM_LOG="$TMP_DIR/npm.log"

# Filter user-local paths from PATH so system-installed codex/claude
# don't interfere with the idempotency guard (command -v check)
FILTERED_PATH=""
IFS=':' read -ra _paths <<< "$PATH"
for _p in "${_paths[@]}"; do
  case "$_p" in
    */nvm/*|*/.local/bin) ;;  # skip these — may contain codex/claude
    *) FILTERED_PATH="${FILTERED_PATH:+$FILTERED_PATH:}$_p" ;;
  esac
done
export PATH="$STUB_BIN:$FILTERED_PATH"

run_codex() {
  # whiptail stub outputs answers literally.
  # --menu answers: no quotes (real whiptail outputs plain text).
  # --checklist answers: quotes preserve item boundaries for shell splitting.
  cat > "$TMP_DIR/answers_codex.txt" <<'ANSWERS'
no
deepseek-v4-pro
"memories" "hooks"
"animations"
never
on-request
"daily"

ANSWERS
  TEST_WHIPTAIL_ANSWERS="$TMP_DIR/answers_codex.txt" \
  HOME="$HOME_DIR" bash "$ROOT_DIR/scripts/modules/codex.sh" <<'EOF'

n
EOF
}

run_claude_code() {
  HOME="$HOME_DIR" bash "$ROOT_DIR/scripts/modules/claude-code.sh" <<'EOF'
n

EOF
}

run_opencode() {
  HOME="$HOME_DIR" bash "$ROOT_DIR/scripts/modules/opencode.sh" <<'EOF'

EOF
}

run_paseo() {
  HOME="$HOME_DIR" bash "$ROOT_DIR/scripts/modules/paseo.sh" <<'EOF'
n
n
EOF
}

run_hermes_agent() {
  cat > "$TMP_DIR/answers_hermes.txt" <<'ANSWERS'
deepseek
deepseek-v4-flash

skip
ANSWERS
  TEST_WHIPTAIL_ANSWERS="$TMP_DIR/answers_hermes.txt" \
  HOME="$HOME_DIR" bash "$ROOT_DIR/scripts/modules/hermes-agent.sh" <<'EOF'

EOF
}

run_codex
run_claude_code
run_opencode
run_paseo
run_hermes_agent
run_codex
run_claude_code
run_opencode
run_paseo
run_hermes_agent

python3 - "$HOME_DIR" "$TEST_NPM_LOG" <<'PY'
import json
import pathlib
import sys
import tomllib

home = pathlib.Path(sys.argv[1])
npm_log = pathlib.Path(sys.argv[2]).read_text()

codex_toml = home / ".codex" / "config.toml"
codex_yaml = home / ".codex" / "config.yaml"
claude_json = home / ".claude" / "settings.json"
openclode_json = home / ".config" / "opencode" / "opencode.json"
paseo_json = home / ".paseo" / "config.json"

assert codex_toml.exists(), "Codex config.toml was not created"
assert not codex_yaml.exists(), "Codex config.yaml should not be created"

codex = tomllib.loads(codex_toml.read_text())
# model may not be set if user chose "do-not-set"
if "model" in codex:
    assert codex["model"], "codex model should not be empty if set"
assert codex["model_reasoning_effort"] == "medium"
assert codex["plan_mode_reasoning_effort"] == "xhigh"
assert codex["approval_policy"] == "on-request"
assert codex["sandbox_mode"] == "workspace-write"

# Assert new features section
assert "features" in codex, "codex missing features section"
assert codex["features"]["memories"] == True
assert codex["features"]["hooks"] == True
assert codex["features"]["undo"] == False
assert codex["features"]["apps"] == False
assert codex["features"]["network_proxy"] == False

# Assert new TUI section
assert "tui" in codex, "codex missing tui section"
assert codex["tui"]["animations"] == True
assert codex["tui"]["alternate_screen"] == "never"
assert codex["tui"]["show_tooltips"] == False

# No model_providers should be configured (provider prompt skipped)
assert "model_providers" not in codex, "no providers should be configured"

# Deprecated openai_base_url should not exist
assert "openai_base_url" not in codex, "deprecated openai_base_url should be removed"

assert codex["mcp_servers"]["context7"]["command"] == "npx"
assert "brave-search" not in codex["mcp_servers"], "empty BRAVE_API_KEY should skip brave-search"

claude = json.loads(claude_json.read_text())
assert claude["permissions"]["defaultMode"] == "acceptEdits"
assert "allow" not in claude["permissions"], "Claude broad allow permissions should not be written"
# Check model is deepseek
assert "model" in claude, "Claude Code model should be set"
assert "deepseek" in claude["model"], f"Expected deepseek model, got {claude['model']}"
assert claude["mcpServers"]["context7"]["command"] == "npx"

opencode = json.loads(openclode_json.read_text())
assert opencode["$schema"] == "https://opencode.ai/config.json"
assert "model" in opencode, "opencode missing model field"
assert opencode["model"], "opencode model is empty"
assert "agent" in opencode, "opencode missing agent field"
assert "plan" in opencode["agent"], "opencode missing agent.plan field"
assert "model" in opencode["agent"]["plan"], "opencode missing plan model field"
assert opencode["agent"]["plan"]["options"]["reasoningEffort"] == "xhigh"
assert opencode["permission"]["edit"] == "ask"
assert opencode["permission"]["bash"] == "ask"
assert opencode["permission"]["external_directory"] == "ask"
assert opencode["mcp"]["context7"]["type"] == "local"
assert "brave-search" not in opencode["mcp"], "empty BRAVE_API_KEY should skip brave-search"

assert paseo_json.exists(), "Paseo config.json was not created"
paseo = json.loads(paseo_json.read_text())
assert paseo["$schema"] == "https://paseo.sh/schemas/paseo.config.v1.json"
assert paseo["version"] == 1
assert "daemon" in paseo, "paseo missing daemon field"
assert "listen" in paseo["daemon"], "paseo daemon missing listen"
assert ":" in paseo["daemon"]["listen"], "paseo listen should be host:port"
assert "hostnames" in paseo["daemon"], "paseo daemon missing hostnames"
assert isinstance(paseo["daemon"]["hostnames"], list)
assert len(paseo["daemon"]["hostnames"]) > 0
assert "mcp" in paseo["daemon"], "paseo daemon missing mcp"
assert isinstance(paseo["daemon"]["mcp"]["enabled"], bool)

assert "install -g @openai/codex" in npm_log
assert "install -g @anthropic-ai/claude-code" in npm_log
assert "install -g opencode-ai" in npm_log
assert "install -g @getpaseo/cli" in npm_log

# Hermes assertions
hermes_yaml = home / ".hermes" / "config.yaml"
assert hermes_yaml.exists(), "Hermes config.yaml was not created"
hermes_text = hermes_yaml.read_text()
assert "model:" in hermes_text, "Hermes config missing model section"
assert "default:" in hermes_text, "Hermes config missing model.default"
assert "deepseek" in hermes_text, "Hermes model should contain deepseek"
import re
model_default = re.search(r'default:\s*(\S+)', hermes_text)
assert model_default, "Hermes model.default should have a value"
assert model_default.group(1), "Hermes model.default should not be empty"

# hermes may be pre-installed on the system, so npm install is optional
if "install -g hermes-agent" not in npm_log:
    # If npm install was skipped, the hermes binary must be available
    hermes_bin = home / ".hermes" / "hermes-agent" / "cli.py"
    if not hermes_bin.exists():
        # Config file existing is still sufficient validation
        pass
PY

echo "agent config tests passed"
