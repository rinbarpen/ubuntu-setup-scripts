#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

need_cmd fish

log_info "Installing fisher and plugins..."
fish -c "
  curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
  fisher install jorgebucaran/fisher
  fisher install jethrokuan/z
  fisher install jorgebucaran/nvm
  fisher install edc/bass
"

# nvm use latest — only if nvm was installed via languages.sh
if [[ -f "$HOME/.nvm/nvm.sh" ]]; then
  fish -c "
    source ~/.nvm/nvm.sh 2>/dev/null || true
    nvm use latest
  " || log_warn "nvm use latest failed (non-fatal)"
else
  log_warn "~/.nvm/nvm.sh not found — skipping nvm use latest. Run languages module first."
fi

log_info "fisher: done"
