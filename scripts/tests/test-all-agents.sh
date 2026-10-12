#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STUB_BIN="$TMP_DIR/bin"
mkdir -p "$STUB_BIN"

# ---- Stub binaries --------------------------------------------------
for cmd in npm whiptail curl omniroute claude; do
  cat > "$STUB_BIN/$cmd" <<EOF
#!/usr/bin/env bash
echo "stub \$cmd \$*" >> "${TMP_DIR}/stub.log"
EOF
  chmod +x "$STUB_BIN/$cmd"
done

# node stub: must output version for pi.sh version check
cat > "$STUB_BIN/node" <<'NODEEOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  echo "v22.12.0"
fi
exit 0
NODEEOF
chmod +x "$STUB_BIN/node"

# whiptail stub with answer file support
cat > "$STUB_BIN/whiptail" <<'WHIPEOF'
#!/usr/bin/env bash
if [[ -f "$TEST_WHIPTAIL_ANSWERS" ]] && [[ -s "$TEST_WHIPTAIL_ANSWERS" ]]; then
  IFS= read -r answer < "$TEST_WHIPTAIL_ANSWERS"
  tail -n +2 "$TEST_WHIPTAIL_ANSWERS" > "${TEST_WHIPTAIL_ANSWERS}.tmp"
  mv "${TEST_WHIPTAIL_ANSWERS}.tmp" "$TEST_WHIPTAIL_ANSWERS"
  printf '%s\n' "$answer" >&2
else
  printf '"daily"\n' >&2
fi
exit 0
WHIPEOF
chmod +x "$STUB_BIN/whiptail"

export TEST_NPM_LOG="$TMP_DIR/npm.log"

# Filter PATH
FILTERED_PATH=""
IFS=':' read -ra _paths <<< "$PATH"
for _p in "${_paths[@]}"; do
  case "$_p" in */nvm/*|*/.local/bin|*/.bun/bin) ;; *) FILTERED_PATH="${FILTERED_PATH:+$FILTERED_PATH:}$_p" ;; esac
done
export PATH="$STUB_BIN:$FILTERED_PATH"

# ---- Helper: run a module and check exit code -----------------------
run_module() {
  local label="$1" home="$2" answers_content="$3" module="$4"
  local answers_file
  answers_file=$(mktemp "$TMP_DIR/${label}_answers.XXXXXX")
  echo "$answers_content" > "$answers_file"
  echo "=== $label ==="
  if TEST_WHIPTAIL_ANSWERS="$answers_file" SKIP_PRESET_SAVE=1 HOME="$home" timeout 30 bash "$ROOT_DIR/scripts/modules/${module}" <<< $'\n\n\n\n\n\n\n\n\n\n' 2>&1; then
    echo "PASS: $label"
  else
    echo "FAIL: $label (exit $?)"
    return 1
  fi
}

# ---- Execute tests --------------------------------------------------
PI_HOME="$TMP_DIR/pi_home"
OMP_HOME="$TMP_DIR/omp_home"
ALL_HOME="$TMP_DIR/all_home"

run_module "pi.sh" "$PI_HOME" \
"omniroute/auto
omniroute/auto
\"daily\" \"chat\"" \
"pi.sh"

run_module "pi.sh (idempotency)" "$PI_HOME" \
"omniroute/auto
omniroute/auto
\"daily\" \"chat\"" \
"pi.sh"

run_module "omp.sh" "$OMP_HOME" \
"omniroute/auto
\"hashAnchoredEdits\" \"snapcompact\"
\"daily\"" \
"omp.sh"

run_module "omp.sh (idempotency)" "$OMP_HOME" \
"omniroute/auto
\"hashAnchoredEdits\" \"snapcompact\"
\"daily\"" \
"omp.sh"

run_module "all-agents.sh" "$ALL_HOME" \
"\"opencode\" \"codex\" \"claude-code\" \"pi\" \"omp\"
omniroute
auto
acceptEdits
auto
on-request
omniroute/auto
\"daily\" \"chat\"" \
"all-agents.sh"

# Check the fresh default before exercising stale values in independent homes.
python3 - "$ALL_HOME" << 'PYEOF'
import json, pathlib, sys
settings = json.loads((pathlib.Path(sys.argv[1]) / ".claude/settings.json").read_text())
assert "CLAUDE_CODE_ATTRIBUTION_HEADER" not in settings["env"]
PYEOF

for old_value in 0 1; do
  CLEANUP_HOME="$TMP_DIR/all_home_cleanup_$old_value"
  mkdir -p "$CLEANUP_HOME/.claude"
  cp "$ALL_HOME/.claude/settings.json" "$CLEANUP_HOME/.claude/settings.json"
  python3 - "$CLEANUP_HOME" "$old_value" << 'PYEOF'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1]) / ".claude/settings.json"
settings = json.loads(path.read_text())
settings["env"]["CLAUDE_CODE_ATTRIBUTION_HEADER"] = sys.argv[2]
settings["env"]["CUSTOM_ENV"] = "keep"
settings["permissions"]["allow"] = ["Read"]
settings["hooks"] = {"Stop": [{"hooks": [{"type": "command", "command": "echo fixture"}]}]}
settings["customField"] = {"keep": True}
path.write_text(json.dumps(settings) + "\n")
PYEOF
  run_module "all-agents.sh (cleanup $old_value)" "$CLEANUP_HOME" \
"\"opencode\" \"codex\" \"claude-code\" \"pi\" \"omp\"
omniroute
auto
acceptEdits
auto
on-request
omniroute/auto
\"daily\" \"chat\"" \
"all-agents.sh"
  python3 - "$CLEANUP_HOME" << 'PYEOF'
import json, pathlib, sys
settings = json.loads((pathlib.Path(sys.argv[1]) / ".claude/settings.json").read_text())
assert "CLAUDE_CODE_ATTRIBUTION_HEADER" not in settings["env"]
assert settings["env"]["CUSTOM_ENV"] == "keep"
assert settings["permissions"]["allow"] == ["Read"]
assert settings["hooks"]["Stop"][0]["hooks"][0]["command"] == "echo fixture"
assert settings["customField"] == {"keep": True}
PYEOF
done

# ---- Validation --------------------------------------------------
python3 << PYEOF
import json, pathlib

pi_h = pathlib.Path("$PI_HOME")
omp_h = pathlib.Path("$OMP_HOME")
all_h = pathlib.Path("$ALL_HOME")
errors = []

# pi checks
pi_s = pi_h / ".pi" / "agent" / "settings.json"
assert pi_s.exists(), "pi settings.json missing"
pi_c = json.loads(pi_s.read_text())
assert pi_c["model"] == "omniroute/auto"
assert pi_c["provider"] == "omniroute"
assert pi_c["baseUrl"] == "http://localhost:20128/v1"
assert pi_c["apiKey"] == "{env:OMNIROUTE_API_KEY}"
assert pi_c["maxTokens"] == 1000000
assert pi_c["cache"]["consistentPrompt"] == True
assert "CLAUDE.md" in pi_c["autoLoad"]

# omp checks
omp_s = omp_h / ".pi" / "agent" / "settings.json"
assert omp_s.exists(), "omp settings.json missing"
omp_c = json.loads(omp_s.read_text())
assert omp_c["features"]["hashAnchoredEdits"] == True
assert omp_c["features"]["snapcompact"] == True
assert omp_c["cache"]["hashAnchoredEdits"] == True
assert omp_c["provider"] == "omniroute"
assert omp_c["baseUrl"] == "http://localhost:20128/v1"

# all-agents checks
cc_s = all_h / ".claude" / "settings.json"
assert cc_s.exists(), "claude-code settings.json missing"
cc = json.loads(cc_s.read_text())
assert cc["model"] == "auto"
assert cc["env"]["ANTHROPIC_BASE_URL"] == "http://localhost:20128"
assert cc["env"]["CLAUDE_CODE_MAX_OUTPUT_TOKENS"] == "1000000"
assert cc["env"]["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] == "1"
assert "CLAUDE_CODE_ATTRIBUTION_HEADER" not in cc["env"]

codex_s = all_h / ".codex" / "config.toml"
assert codex_s.exists(), "codex config.toml missing"
ct = codex_s.read_text()
assert 'model = ' in ct
assert 'model_provider = "omniroute"' in ct
assert '[model_providers.omniroute]' in ct

oc_s = all_h / ".config" / "opencode" / "opencode.json"
assert oc_s.exists(), "opencode config missing"
oc = json.loads(oc_s.read_text())
assert oc["model"] == "omniroute/auto"
assert "omniroute" in oc["provider"]

all_pi_s = all_h / ".pi" / "agent" / "settings.json"
assert all_pi_s.exists(), "all-agents pi settings missing"
all_pi = json.loads(all_pi_s.read_text())
assert "features" in all_pi, "omp features not merged into shared settings"

print("\n=== All validations passed ===")
PYEOF

echo "=== test-all-agents.sh: ALL TESTS PASSED ==="
