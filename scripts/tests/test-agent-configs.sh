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
printf '"daily"\n' >&2
exit 0
EOF
chmod +x "$STUB_BIN/whiptail"

export TEST_NPM_LOG="$TMP_DIR/npm.log"
export PATH="$STUB_BIN:$PATH"

run_codex_cc() {
  HOME="$HOME_DIR" bash "$ROOT_DIR/scripts/modules/codex-cc.sh" <<'EOF'
n

EOF
}

run_opencode() {
  HOME="$HOME_DIR" bash "$ROOT_DIR/scripts/modules/opencode.sh" <<'EOF'

EOF
}

run_codex_cc
run_opencode
run_codex_cc
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
opencode_json = home / ".config" / "opencode" / "opencode.json"

assert codex_toml.exists(), "Codex config.toml was not created"
assert not codex_yaml.exists(), "Codex config.yaml should not be created"

codex = tomllib.loads(codex_toml.read_text())
assert codex["model"] == "gpt-5.5"
assert codex["model_reasoning_effort"] == "medium"
assert codex["plan_mode_reasoning_effort"] == "xhigh"
assert codex["approval_policy"] == "on-request"
assert codex["sandbox_mode"] == "workspace-write"
assert codex["mcp_servers"]["context7"]["command"] == "npx"
assert "brave-search" not in codex["mcp_servers"], "empty BRAVE_API_KEY should skip brave-search"

claude = json.loads(claude_json.read_text())
assert claude["permissions"]["defaultMode"] == "acceptEdits"
assert "allow" not in claude["permissions"], "Claude broad allow permissions should not be written"
assert claude["mcpServers"]["context7"]["command"] == "npx"

opencode = json.loads(opencode_json.read_text())
assert opencode["$schema"] == "https://opencode.ai/config.json"
assert opencode["model"] == "deepseek/deepseek-v4-flash"
assert opencode["agent"]["plan"]["model"] == "openai/gpt-5.5"
assert opencode["agent"]["plan"]["options"]["reasoningEffort"] == "xhigh"
assert opencode["permission"]["edit"] == "ask"
assert opencode["permission"]["bash"] == "ask"
assert opencode["permission"]["external_directory"] == "ask"
assert opencode["mcp"]["context7"]["type"] == "local"
assert "brave-search" not in opencode["mcp"], "empty BRAVE_API_KEY should skip brave-search"

assert "install -g opencode-ai" in npm_log
PY

echo "agent config tests passed"
