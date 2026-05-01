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
export PATH="$STUB_BIN:$PATH"

run_codex() {
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

run_codex
run_claude_code
run_opencode
run_codex
run_claude_code
run_opencode

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

assert "install -g @openai/codex" in npm_log
assert "install -g @anthropic-ai/claude-code" in npm_log
assert "install -g opencode-ai" in npm_log
PY

echo "agent config tests passed"
