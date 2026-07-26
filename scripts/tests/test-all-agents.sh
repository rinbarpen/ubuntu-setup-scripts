#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STUB_BIN="$TMP_DIR/bin"
mkdir -p "$STUB_BIN"

# ---- Stub binaries --------------------------------------------------
for cmd in npm whiptail; do
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
"deepseek
deepseek-v4-flash
\"daily\" \"chat\"" \
"pi.sh"

run_module "pi.sh (idempotency)" "$PI_HOME" \
"deepseek
deepseek-v4-flash
\"daily\" \"chat\"" \
"pi.sh"

run_module "omp.sh" "$OMP_HOME" \
"deepseek
deepseek-v4-pro
\"hashAnchoredEdits\" \"snapcompact\"
\"daily\"" \
"omp.sh"

run_module "omp.sh (idempotency)" "$OMP_HOME" \
"deepseek
deepseek-v4-pro
\"hashAnchoredEdits\" \"snapcompact\"
\"daily\"" \
"omp.sh"

run_module "all-agents.sh" "$ALL_HOME" \
"\"opencode\" \"codex\" \"claude-code\" \"pi\" \"omp\"
deepseek
deepseek-v4-flash
acceptEdits
deepseek-v4-pro
on-request
deepseek/deepseek-v4-flash
none
\"daily\" \"chat\"" \
"all-agents.sh"

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
assert pi_c["model"] == "deepseek-v4-flash"
assert pi_c["provider"] == "deepseek"
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

# all-agents checks
cc_s = all_h / ".claude" / "settings.json"
assert cc_s.exists(), "claude-code settings.json missing"
cc = json.loads(cc_s.read_text())
assert cc["model"] == "deepseek-v4-flash"
assert cc["env"]["CLAUDE_CODE_MAX_OUTPUT_TOKENS"] == "1000000"
assert cc["env"]["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] == "1"

codex_s = all_h / ".codex" / "config.toml"
assert codex_s.exists(), "codex config.toml missing"
ct = codex_s.read_text()
assert 'model = ' in ct

oc_s = all_h / ".config" / "opencode" / "opencode.json"
assert oc_s.exists(), "opencode config missing"
oc = json.loads(oc_s.read_text())
assert "deepseek" in oc["model"]

all_pi_s = all_h / ".pi" / "agent" / "settings.json"
assert all_pi_s.exists(), "all-agents pi settings missing"
all_pi = json.loads(all_pi_s.read_text())
assert "features" in all_pi, "omp features not merged into shared settings"

print("\n=== All validations passed ===")
PYEOF

echo "=== test-all-agents.sh: ALL TESTS PASSED ==="
