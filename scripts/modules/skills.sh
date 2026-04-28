#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$CLAUDE_SETTINGS")"

SKILLS_BASE="$HOME/.claude/skills"
mkdir -p "$SKILLS_BASE"

if command -v whiptail &>/dev/null; then
  SKILL_CHOICES=$(whiptail --title "Claude Code Skills" --checklist \
    "Select skill collections to install:" 16 70 4 \
    "superpowers"      "核心 superpowers 技能系统"               ON  \
    "ui-ux"            "UI/UX Pro Max 设计技能"                  OFF \
    "ai-research"      "AI 自动调研 (auto-research-in-sleeping)"  OFF \
    "anthropic-skills" "Anthropic 官方技能集 (科学/研究/写作)"    OFF \
    3>&1 1>&2 2>&3) || SKILL_CHOICES=""
  SKILL_SELECTED=$(echo "$SKILL_CHOICES" | tr -d '"')
else
  log_warn "whiptail not found — skipping skills selection"
  SKILL_SELECTED=""
fi

# Helper: clone or pull a skill collection
_install_skill_collection() {
  local name="$1" url="$2"
  local dest="${SKILLS_BASE}/${name}"
  if [[ -z "$url" ]]; then
    log_warn "No URL for '${name}' — skipping"
    return
  fi
  if [[ -d "${dest}/.git" ]]; then
    log_info "Updating skill collection: ${name}"
    git -C "$dest" pull --ff-only || log_warn "git pull failed for ${name}"
  else
    log_info "Installing skill collection: ${name}"
    git clone "$url" "$dest" || log_warn "git clone failed for ${name}"
  fi
}

SKILLS_INSTALLED=0
for skill in $SKILL_SELECTED; do
  case "$skill" in
    superpowers)
      read -r -p "superpowers repo URL: " _url
      _install_skill_collection "superpowers" "$_url"
      ;;
    ui-ux)
      read -r -p "ui-ux-pro-max repo URL: " _url
      _install_skill_collection "ui-ux" "$_url"
      ;;
    ai-research)
      read -r -p "ai-research repo URL: " _url
      _install_skill_collection "ai-research" "$_url"
      ;;
    anthropic-skills)
      read -r -p "anthropic-skills repo URL: " _url
      _install_skill_collection "anthropic-skills" "$_url"
      ;;
  esac
  SKILLS_INSTALLED=1
done

if [[ "$SKILLS_INSTALLED" -eq 1 ]]; then
  python3 - "$CLAUDE_SETTINGS" "$SKILLS_BASE" << 'PYEOF'
import json, sys
path, skills_dir = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        s = json.load(f)
except Exception:
    s = {}
s['skillsDirectory'] = skills_dir
with open(path, 'w') as f:
    json.dump(s, f, indent=2)
    f.write('\n')
PYEOF
  log_info "skillsDirectory set to $SKILLS_BASE"
fi

log_info "skills: done"
