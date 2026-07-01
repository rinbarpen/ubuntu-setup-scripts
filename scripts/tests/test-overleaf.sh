#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STUB_BIN="$TMP_DIR/bin"
HOME_DIR="$TMP_DIR/home"
mkdir -p "$STUB_BIN" "$HOME_DIR"

# Stub docker (supports compose subcommand, ps, up, exec, commit)
cat > "$STUB_BIN/docker" <<'DOCKEREOF'
#!/usr/bin/env bash
if [[ "$1" == "compose" && "$2" == "version" ]]; then
  echo "Docker Compose version v2.24.0"
  exit 0
fi
if [[ "$1" == "compose" && ("$3" == "ps" || "$*" == *" ps"*) ]]; then
  echo ""  # no containers running
  exit 0
fi
if [[ "$1" == "compose" && "$*" == *" up -d"* ]]; then
  echo "stub: compose up -d"
  exit 0
fi
if [[ "$1" == "compose" && "$*" == *" exec"* ]]; then
  echo "stub: compose exec"
  exit 0
fi
if [[ "$1" == "compose" && "$2" == "down" ]]; then
  echo "stub: compose down"
  exit 0
fi
if [[ "$1" == "ps" ]]; then
  echo ""  # no containers
  exit 0
fi
if [[ "$1" == "commit" ]]; then
  echo "stub: docker commit overleaf as overleaf-custom:latest"
  exit 0
fi
exit 0
DOCKEREOF
chmod +x "$STUB_BIN/docker"

# Stub curl (always succeeds)
cat > "$STUB_BIN/curl" <<'CURLEOF'
#!/usr/bin/env bash
exit 0
CURLEOF
chmod +x "$STUB_BIN/curl"

# Stub lsof (port free)
cat > "$STUB_BIN/lsof" <<'LSOFEOF'
#!/usr/bin/env bash
exit 1
LSOFEOF
chmod +x "$STUB_BIN/lsof"

# Stub whiptail — return "internal" for menu, OK for msgbox
cat > "$STUB_BIN/whiptail" <<'WEOF'
#!/usr/bin/env bash
if [[ "$*" == *--msgbox* ]]; then exit 0; fi
if [[ "$*" == *--menu* ]] || [[ "$*" == *--title* ]]; then
  printf '%s\n' "internal"
  exit 0
fi
if [[ "$*" == *--yesno* ]]; then exit 0; fi
exit 0
WEOF
chmod +x "$STUB_BIN/whiptail"

export PATH="$STUB_BIN:$PATH"

echo "Running overleaf module with stubs..."

# Run module with preset answers (empty lines = use defaults, "n" = skip all confirms)
# Mongo mode is "internal" from whiptail stub
# No containers running from docker ps stub, so idempotency check passes through
printf '\n%.0s' {1..15} | HOME="$HOME_DIR" bash "$ROOT_DIR/scripts/modules/overleaf.sh"

# Verify outputs
python3 - "$HOME_DIR" <<'PY'
import pathlib, sys

home = pathlib.Path(sys.argv[1])
compose = home / "overleaf" / "docker-compose.yml"
envfile = home / "overleaf" / ".env"
fish_func = home / ".config" / "fish" / "functions" / "overleaf.fish"
bashrc = home / ".bashrc"

assert compose.exists(), f"docker-compose.yml not created at {compose}"
assert envfile.exists(), f".env file not created at {envfile}"
assert fish_func.exists(), f"fish function not created at {fish_func}"
assert bashrc.exists(), f".bashrc not updated at {bashrc}"

compose_text = compose.read_text()
assert "sharelatex" in compose_text, "compose missing sharelatex service"
assert "redis" in compose_text, "compose missing redis service"
assert "mongo" in compose_text, "compose missing mongo service (internal mode)"
assert "overleaf-custom" not in compose_text, "compose should not have custom image (no commit)"

env_text = envfile.read_text()
assert "OVERLEAF_SITE_URL" in env_text, "env missing SITE_URL"
assert "OVERLEAF_PORT" in env_text, "env missing PORT"
assert "mongo" in env_text, "env missing mongo URL"

fish_text = fish_func.read_text()
assert "overleaf-compose" in fish_text, "fish missing compose helper"
assert "overleaf-logs" in fish_text, "fish missing logs helper"
assert "overleaf-shell" in fish_text, "fish missing shell helper"

bash_text = bashrc.read_text()
assert "overleaf-compose" in bash_text, "bash missing compose helper"

# Run second time to test idempotency — stub docker ps now returns nothing,
# so the "already running" check will skip. Confirm with second env.
home2 = pathlib.Path(str(home) + "2")
import subprocess, os
env2 = os.environ.copy()
env2["HOME"] = str(home2)
result = subprocess.run(
    ["bash", str(pathlib.Path(sys.argv[0]).parent.parent.parent / "scripts/modules/overleaf.sh")],
    env=env2,
    input=b"\n" * 15,
    capture_output=True,
    timeout=30,
)
# Should have created files in home2 too
compose2 = home2 / "overleaf" / "docker-compose.yml"
assert compose2.exists(), "Second run should create compose in new home"

print("All assertions passed.")
PY

echo "overleaf integration tests passed"
