#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"

need_cmd whiptail

sudo_check

# Ordered list — respects dependencies (languages before npm-based AI CLIs, shell before fisher)
ORDERED=(ubuntu-base languages shell fisher git zerotier zellij browsers vms openclaw opencode codex claude-code vibma skills)

CHOICES=$(whiptail --title "Ubuntu Setup" --checklist \
  "Select modules to install (SPACE to toggle, ENTER to confirm):" 26 60 12 \
  "ubuntu-base"  "System tools, Docker, xrdp"          ON \
  "languages"    "nvm/Node, Python, Rust, Go, uv"      ON \
  "shell"        "fish shell + proxy functions"         ON \
  "fisher"       "fisher + z, nvm, bass plugins"        ON \
  "git"          "git config, SSH key, git-lfs"         ON \
  "zerotier"     "ZeroTier VPN"                        OFF \
  "zellij"       "zellij terminal multiplexer"         ON \
  "browsers"     "Chrome, Firefox"                     OFF \
  "vms"          "VirtualBox, QEMU/KVM"                OFF \
   "openclaw"     "openclaw (npm)"                      OFF \
   "opencode"     "opencode CLI + MCP"                  ON \
   "codex"        "codex CLI + MCP"                     ON \
   "claude-code"  "Claude Code + MCP"                   ON \
   "vibma"        "Vibma MCP + Figma plugin + skills"   OFF \
  "skills"       "Claude Code skill collections"       OFF \
  3>&1 1>&2 2>&3) || { log_warn "Cancelled."; exit 0; }

# Strip quotes from whiptail output
SELECTED=$(echo "$CHOICES" | tr -d '"')

declare -A EXIT_CODES

for module in "${ORDERED[@]}"; do
  if echo "$SELECTED" | grep -Fqw "$module"; then
    log_info "==> Running module: $module"
    if bash "${SCRIPT_DIR}/modules/${module}.sh"; then
      EXIT_CODES[$module]="OK"
    else
      rc=$?
      EXIT_CODES[$module]="FAIL (exit $rc)"
      log_warn "Module $module failed — continuing"
    fi
  fi
done

echo ""
log_info "===== Setup Summary ====="
for module in "${ORDERED[@]}"; do
  if [[ -n "${EXIT_CODES[$module]+x}" ]]; then
    printf "  %-16s %s\n" "$module" "${EXIT_CODES[$module]}"
  fi
done
