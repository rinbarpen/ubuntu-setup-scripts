#!/usr/bin/env bash
# Shared utilities for all setup modules

# Colors
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_err()   { echo -e "${RED}[ERR]${NC}   $*" >&2; }

# Assert command exists or abort current script
need_cmd() {
  if ! command -v "$1" &>/dev/null; then
    log_err "Required command not found: $1"
    exit 1
  fi
}

# Prompt y/n. Returns 0 for yes, 1 for no.
confirm() {
  local prompt="${1:-Continue?}"
  read -r -p "${prompt} [y/N] " reply
  [[ "${reply,,}" =~ ^y ]]
}

# Acquire sudo upfront and keep alive
sudo_check() {
  sudo -v
  while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &
}
