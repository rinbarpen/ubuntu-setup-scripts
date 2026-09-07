#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE_SKILL="$ROOT_DIR/skills/ego-browser"
CODEX_HOME_DIR=${CODEX_HOME:-"$HOME/.codex"}
TARGET_SKILL="$CODEX_HOME_DIR/skills/ego-browser"
MODE=${1:-all}

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This installer must be run on macOS (Darwin)." >&2
  exit 2
fi

[ -f "$SOURCE_SKILL/SKILL.md" ] || {
  echo "Missing bundled ego-browser skill: $SOURCE_SKILL" >&2
  exit 1
}

mkdir -p "$CODEX_HOME_DIR/skills"
if [ -e "$TARGET_SKILL" ]; then
  BACKUP_SKILL="${TARGET_SKILL}.backup.$(date +%Y%m%d%H%M%S)"
  mv "$TARGET_SKILL" "$BACKUP_SKILL"
  printf '%s\n' "Backed up existing skill to $BACKUP_SKILL"
fi
cp -R "$SOURCE_SKILL" "$TARGET_SKILL"
chmod +x "$TARGET_SKILL/scripts/install.sh"
printf '%s\n' "Installed ego-browser (ego-lite) skill to $TARGET_SKILL"

case "$MODE" in
  --skill-only)
    exit 0
    ;;
  all)
    exec sh "$TARGET_SKILL/scripts/install.sh"
    ;;
  *)
    echo "Usage: $0 [--skill-only]" >&2
    exit 64
    ;;
esac
