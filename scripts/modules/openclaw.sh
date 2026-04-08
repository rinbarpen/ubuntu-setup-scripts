#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

need_cmd npm

log_info "Installing openclaw..."
npm install -g openclaw
log_info "openclaw $(openclaw --version 2>/dev/null || echo 'installed')"
