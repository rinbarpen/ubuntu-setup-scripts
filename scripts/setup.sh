#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"

need_cmd whiptail

sudo_check

# Ordered list — respects dependencies (languages before fisher, shell before fisher)
ORDERED=(ubuntu-base languages shell fisher git zerotier zellij browsers vms openclaw codex-cc)

CHOICES=$(whiptail --title "Ubuntu Setup" --checklist \
  "Select modules to install (SPACE to toggle, ENTER to confirm):" 24 60 11 \
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
  "codex-cc"     "codex CLI + Claude Code"             ON \
  3>&1 1>&2 2>&3) || { log_warn "Cancelled."; exit 0; }

# Strip quotes from whiptail output
SELECTED=$(echo "$CHOICES" | tr -d '"')

declare -A EXIT_CODES

for module in "${ORDERED[@]}"; do
  if echo "$SELECTED" | grep -qw "$module"; then
    log_info "==> Running module: $module"
    if bash "${SCRIPT_DIR}/modules/${module}.sh"; then
      EXIT_CODES[$module]="OK"
    else
      EXIT_CODES[$module]="FAIL (exit $?)"
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
