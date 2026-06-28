#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

need_cmd docker
need_cmd python3
need_cmd curl
need_cmd openssl
# lsof is optional — port conflict check will be skipped if absent

if ! docker compose version &>/dev/null; then
  log_err "docker compose plugin not found — run ubuntu-base module first"
  exit 1
fi

install_overleaf() {
  OVERLEAF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/overleaf"
  OVERLEAF_COMPOSE="${OVERLEAF_DIR}/docker-compose.yml"
  OVERLEAF_ENV="${OVERLEAF_DIR}/.env"

  # ── Idempotency ──────────────────────────────────────────────────────────
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^overleaf$'; then
    log_info "Overleaf container is already running"
    if confirm "Recreate Overleaf containers?"; then
      log_info "Stopping existing containers..."
      cd "$OVERLEAF_DIR" && docker compose down 2>/dev/null || true
    else
      log_info "overleaf: skipped"
      return
    fi
  fi

  mkdir -p "$OVERLEAF_DIR"

  # ── Read existing values from .env ───────────────────────────────────────
  if [[ -f "$OVERLEAF_ENV" ]]; then
    eval "$(
      python3 - "$OVERLEAF_ENV" << 'PYEOF' 2>/dev/null || echo ""
import sys, re
lines = open(sys.argv[1]).read().splitlines()
for line in lines:
    line = line.strip()
    if "=" in line and line.startswith("OVERLEAF_"):
        key, val = line.split("=", 1)
        val = val.strip("'\"")
        # Shell-safe quoting
        print(f'{key}="{val}"')
PYEOF
    )"
  fi

  # ── Defaults ─────────────────────────────────────────────────────────────
  OVERLEAF_SITE_URL="${OVERLEAF_SITE_URL:-http://localhost:25681}"
  OVERLEAF_APP_NAME="${OVERLEAF_APP_NAME:-Overleaf @Rczx}"
  OVERLEAF_PORT="${OVERLEAF_PORT:-25681}"
  OVERLEAF_MONGO_URL="${OVERLEAF_MONGO_URL:-mongodb://mongo/sharelatex}"
  OVERLEAF_EMAIL="${OVERLEAF_EMAIL:-}"
  OVERLEAF_INVITE_TOKEN_SECRET="${OVERLEAF_INVITE_TOKEN_SECRET:-}"
  OVERLEAF_LEFT_FOOTER="${OVERLEAF_LEFT_FOOTER:-}"
  OVERLEAF_RIGHT_FOOTER="${OVERLEAF_RIGHT_FOOTER:-}"
  OVERLEAF_EMAIL_FROM_ADDRESS="${OVERLEAF_EMAIL_FROM_ADDRESS:-}"
  OVERLEAF_EMAIL_SMTP_HOST="${OVERLEAF_EMAIL_SMTP_HOST:-}"
  OVERLEAF_EMAIL_SMTP_PORT="${OVERLEAF_EMAIL_SMTP_PORT:-587}"
  OVERLEAF_EMAIL_SMTP_SECURE="${OVERLEAF_EMAIL_SMTP_SECURE:-false}"
  OVERLEAF_EMAIL_SMTP_USER="${OVERLEAF_EMAIL_SMTP_USER:-}"
  OVERLEAF_EMAIL_SMTP_PASS="${OVERLEAF_EMAIL_SMTP_PASS:-}"
  OVERLEAF_EMAIL_SMTP_TLS_REJECT_UNAUTH="${OVERLEAF_EMAIL_SMTP_TLS_REJECT_UNAUTH:-}"
  OVERLEAF_EMAIL_SMTP_IGNORE_TLS="${OVERLEAF_EMAIL_SMTP_IGNORE_TLS:-}"
  OVERLEAF_INSTALL_TEXLIVE="${OVERLEAF_INSTALL_TEXLIVE:-false}"
  OVERLEAF_INSTALL_CJK="${OVERLEAF_INSTALL_CJK:-false}"
  OVERLEAF_INSTALL_XELATEX="${OVERLEAF_INSTALL_XELATEX:-false}"
  OVERLEAF_IMAGE="${OVERLEAF_IMAGE:-sharelatex/sharelatex:with-texlive}"

  # ── Whiptail prompts ────────────────────────────────────────────────────
  if command -v whiptail &>/dev/null; then
    whiptail --msgbox "Overleaf (ShareLaTeX Community Edition) self-hosted setup.

This will deploy Overleaf via Docker Compose with:
  - Overleaf web app + Redis + MongoDB (replica set)
  - Optional: TeX Live, CJK fonts, XeLaTeX

Requirements: Docker + docker compose plugin." 14 60
  fi

  # Site URL
  _url_prompt="Overleaf public URL"
  if [[ -n "$OVERLEAF_SITE_URL" ]]; then
    _url_prompt="${_url_prompt} [${OVERLEAF_SITE_URL}]"
  fi
  read -r -p "${_url_prompt}: " _url_input
  [[ -n "$_url_input" ]] && OVERLEAF_SITE_URL="$_url_input"

  # App name
  read -r -p "Display name [${OVERLEAF_APP_NAME}]: " _name_input
  [[ -n "$_name_input" ]] && OVERLEAF_APP_NAME="$_name_input"

  # Port
  read -r -p "Host port [${OVERLEAF_PORT}]: " _port_input
  [[ -n "$_port_input" ]] && OVERLEAF_PORT="$_port_input"
  if command -v lsof &>/dev/null; then
    _pid_on_port=$(lsof -ti :"$OVERLEAF_PORT" 2>/dev/null || true)
    if [[ -n "$_pid_on_port" ]]; then
      log_warn "Port $OVERLEAF_PORT is used by PID $_pid_on_port"
      if ! confirm "Continue anyway?"; then
        log_err "Aborted."
        exit 1
      fi
    fi
  else
    log_warn "lsof not found — skipping port conflict check"
  fi

  # Admin email
  read -r -p "Admin email (optional): " _email_input
  [[ -n "$_email_input" ]] && OVERLEAF_EMAIL="$_email_input"

  # SMTP
  if confirm "Configure SMTP for email notifications?"; then
    read -r -p "SMTP host: " OVERLEAF_EMAIL_SMTP_HOST
    read -r -p "SMTP port [${OVERLEAF_EMAIL_SMTP_PORT}]: " _smtp_port
    [[ -n "$_smtp_port" ]] && OVERLEAF_EMAIL_SMTP_PORT="$_smtp_port"
    read -r -p "SMTP user: " OVERLEAF_EMAIL_SMTP_USER
    read -r -s -p "SMTP password: " OVERLEAF_EMAIL_SMTP_PASS; echo ""
    confirm "Use TLS (SMTP secure)?" && OVERLEAF_EMAIL_SMTP_SECURE="true" || OVERLEAF_EMAIL_SMTP_SECURE="false"
    read -r -p "SMTP from address: " OVERLEAF_EMAIL_FROM_ADDRESS
    confirm "Reject unauthorized TLS certs?" && OVERLEAF_EMAIL_SMTP_TLS_REJECT_UNAUTH="true" || OVERLEAF_EMAIL_SMTP_TLS_REJECT_UNAUTH="false"
    confirm "Ignore TLS?" && OVERLEAF_EMAIL_SMTP_IGNORE_TLS="true" || OVERLEAF_EMAIL_SMTP_IGNORE_TLS="false"
  fi

  # Post-install options
  if confirm "Install full TeX Live (~5GB)? [recommended for production]"; then
    OVERLEAF_INSTALL_TEXLIVE="true"
  fi
  if confirm "Install Chinese CJK fonts (Noto CJK)?"; then
    OVERLEAF_INSTALL_CJK="true"
  fi
  if confirm "Install XeLaTeX support (xelatex engine)?"; then
    OVERLEAF_INSTALL_XELATEX="true"
  fi

  # ── Export for Python3 heredocs ─────────────────────────────────────────
  export OVERLEAF_DIR OVERLEAF_SITE_URL OVERLEAF_APP_NAME OVERLEAF_PORT
  export OVERLEAF_MONGO_URL OVERLEAF_EMAIL
  export OVERLEAF_INVITE_TOKEN_SECRET
  export OVERLEAF_LEFT_FOOTER OVERLEAF_RIGHT_FOOTER
  export OVERLEAF_EMAIL_FROM_ADDRESS
  export OVERLEAF_EMAIL_SMTP_HOST OVERLEAF_EMAIL_SMTP_PORT
  export OVERLEAF_EMAIL_SMTP_SECURE OVERLEAF_EMAIL_SMTP_USER OVERLEAF_EMAIL_SMTP_PASS
  export OVERLEAF_EMAIL_SMTP_TLS_REJECT_UNAUTH OVERLEAF_EMAIL_SMTP_IGNORE_TLS
  export OVERLEAF_IMAGE

  # ── Auto-generate INVITE_TOKEN_SECRET ──────────────────────────────────
  if [[ -z "$OVERLEAF_INVITE_TOKEN_SECRET" ]]; then
    OVERLEAF_INVITE_TOKEN_SECRET="$(openssl rand -base64 32)"
    export OVERLEAF_INVITE_TOKEN_SECRET
    log_info "Generated OVERLEAF_INVITE_TOKEN_SECRET"
  fi

  # ── Write .env file ─────────────────────────────────────────────────────
  python3 - "$OVERLEAF_ENV" << 'PYEOF'
import os, pathlib, sys

path = pathlib.Path(sys.argv[1])

def q(s):
    """Quote value if contains special chars."""
    if not s:
        return '""'
    if any(c in s for c in ' #"\'$`'):
        return "'" + s.replace("'", "'\\''") + "'"
    return s

env = {
    "OVERLEAF_SITE_URL": os.environ.get("OVERLEAF_SITE_URL", ""),
    "OVERLEAF_APP_NAME": os.environ.get("OVERLEAF_APP_NAME", "Overleaf @Rczx"),
    "OVERLEAF_PORT": os.environ.get("OVERLEAF_PORT", "25681"),
    "OVERLEAF_MONGO_URL": os.environ.get("OVERLEAF_MONGO_URL", "mongodb://mongo/sharelatex"),
    "OVERLEAF_EMAIL": os.environ.get("OVERLEAF_EMAIL", ""),
    "OVERLEAF_INVITE_TOKEN_SECRET": os.environ.get("OVERLEAF_INVITE_TOKEN_SECRET", ""),
    "OVERLEAF_LEFT_FOOTER": os.environ.get("OVERLEAF_LEFT_FOOTER", ""),
    "OVERLEAF_RIGHT_FOOTER": os.environ.get("OVERLEAF_RIGHT_FOOTER", ""),
    "OVERLEAF_IMAGE": os.environ.get("OVERLEAF_IMAGE", "sharelatex/sharelatex:with-texlive"),
    "OVERLEAF_EMAIL_FROM_ADDRESS": os.environ.get("OVERLEAF_EMAIL_FROM_ADDRESS", ""),
    "OVERLEAF_EMAIL_SMTP_HOST": os.environ.get("OVERLEAF_EMAIL_SMTP_HOST", ""),
    "OVERLEAF_EMAIL_SMTP_PORT": os.environ.get("OVERLEAF_EMAIL_SMTP_PORT", "587"),
    "OVERLEAF_EMAIL_SMTP_SECURE": os.environ.get("OVERLEAF_EMAIL_SMTP_SECURE", "false"),
    "OVERLEAF_EMAIL_SMTP_USER": os.environ.get("OVERLEAF_EMAIL_SMTP_USER", ""),
    "OVERLEAF_EMAIL_SMTP_PASS": os.environ.get("OVERLEAF_EMAIL_SMTP_PASS", ""),
    "OVERLEAF_EMAIL_SMTP_TLS_REJECT_UNAUTH": os.environ.get("OVERLEAF_EMAIL_SMTP_TLS_REJECT_UNAUTH", ""),
    "OVERLEAF_EMAIL_SMTP_IGNORE_TLS": os.environ.get("OVERLEAF_EMAIL_SMTP_IGNORE_TLS", ""),
}

lines = []
for key, val in env.items():
    lines.append(f"{key}={q(val)}\n")

path.write_text("".join(lines))
PYEOF
  log_info ".env written to $OVERLEAF_ENV"
  chmod 600 "$OVERLEAF_ENV"

  # ── Docker compose up ───────────────────────────────────────────────────
  log_info "Starting Overleaf containers..."
  cd "$OVERLEAF_DIR"
  if ! docker compose up -d; then
    log_err "docker compose up failed — check 'docker compose -f ${OVERLEAF_COMPOSE} logs sharelatex'"
    exit 1
  fi

  # ── Wait for readiness ──────────────────────────────────────────────────
  log_info "Waiting for Overleaf to respond (timeout: 180s)..."
  _elapsed=0
  while [[ $_elapsed -lt 180 ]]; do
    if curl -sf "http://localhost:${OVERLEAF_PORT}" >/dev/null 2>&1; then
      log_info "Overleaf ready at http://localhost:${OVERLEAF_PORT}"
      break
    fi
    sleep 5
    _elapsed=$((_elapsed + 5))
  done
  if [[ $_elapsed -ge 180 ]]; then
    log_warn "Overleaf did not respond within 180s — check 'docker compose logs sharelatex'"
  fi

  # ── Post-install ────────────────────────────────────────────────────────
  if [[ "$OVERLEAF_INSTALL_TEXLIVE" == "true" ]]; then
    log_info "Installing full TeX Live (~5GB, may take 30+ minutes)..."
    docker compose exec -T sharelatex tlmgr install scheme-full 2>&1 | tail -5 || \
      log_warn "TeX Live install failed (may need manual install)"
  fi

  if [[ "$OVERLEAF_INSTALL_CJK" == "true" ]]; then
    log_info "Installing CJK fonts..."
    docker compose exec -T sharelatex bash -c "
      apt-get update -qq 2>/dev/null
      apt-get install -y -qq fonts-noto-cjk 2>&1 | tail -3
      fc-cache -fv 2>&1 | tail -3
    " || log_warn "CJK install failed"
  fi

  if [[ "$OVERLEAF_INSTALL_XELATEX" == "true" ]]; then
    log_info "Installing XeLaTeX support..."
    docker compose exec -T sharelatex bash -c "
      if ! command -v xelatex &>/dev/null; then
        apt-get install -y -qq texlive-xetex 2>&1 | tail -3
      else
        echo 'xelatex already available'
      fi
    " || log_warn "XeLaTeX install failed"
  fi

  # ── docker commit ───────────────────────────────────────────────────────
  if [[ "$OVERLEAF_INSTALL_TEXLIVE" == "true" || "$OVERLEAF_INSTALL_CJK" == "true" || "$OVERLEAF_INSTALL_XELATEX" == "true" ]]; then
    if confirm "Commit container to preserve changes across restarts? (Creates overleaf-custom:latest)"; then
      log_info "Committing container as overleaf-custom:latest..."
      docker commit overleaf overleaf-custom:latest
      OVERLEAF_IMAGE="overleaf-custom:latest"
      export OVERLEAF_IMAGE

      # Regenerate .env with new image
      python3 - "$OVERLEAF_ENV" "$OVERLEAF_IMAGE" << 'PYEOF2'
import os, pathlib, sys
path = pathlib.Path(sys.argv[1])
new_image = sys.argv[2]

lines = path.read_text().splitlines(True)
out = []
for line in lines:
    if line.startswith("OVERLEAF_IMAGE="):
        out.append(f"OVERLEAF_IMAGE={new_image}\n")
    else:
        out.append(line)
path.write_text("".join(out))
PYEOF2

      log_info ".env updated to use overleaf-custom:latest"
    fi
  fi

  # ── Shell integration ───────────────────────────────────────────────────
  FISH_FUNC_DIR="$HOME/.config/fish/functions"
  mkdir -p "$FISH_FUNC_DIR"

  cat > "${FISH_FUNC_DIR}/overleaf.fish" << FISHEOF
function overleaf-compose
    docker compose -f ${OVERLEAF_DIR}/docker-compose.yml \$argv
end

function overleaf-logs
    overleaf-compose logs -f \$argv
end

function overleaf-restart
    overleaf-compose restart \$argv
end

function overleaf-shell
    overleaf-compose exec sharelatex bash
end

function overleaf-ps
    overleaf-compose ps
end

function overleaf-up
    overleaf-compose up -d
end

function overleaf-down
    overleaf-compose down
end

function overleaf-update
    overleaf-compose pull
    overleaf-compose up -d
end
FISHEOF

  if ! grep -q "# overleaf (added by setup)" "$HOME/.bashrc" 2>/dev/null; then
    cat >> "$HOME/.bashrc" << BASHEOF

# overleaf (added by setup)
OVERLEAF_COMPOSE="${OVERLEAF_DIR}/docker-compose.yml"
overleaf-compose() { docker compose -f "\$OVERLEAF_COMPOSE" "\$@"; }
overleaf-logs()    { overleaf-compose logs -f "\$@"; }
overleaf-restart() { overleaf-compose restart "\$@"; }
overleaf-shell()   { overleaf-compose exec sharelatex bash; }
overleaf-ps()      { overleaf-compose ps; }
overleaf-up()      { overleaf-compose up -d; }
overleaf-down()    { overleaf-compose down; }
overleaf-update()  { overleaf-compose pull && overleaf-compose up -d; }
BASHEOF
  fi

  # ── Final output ────────────────────────────────────────────────────────
  log_info "overleaf: done"
  echo ""
  echo "  URL:           http://localhost:${OVERLEAF_PORT}"
  echo "  Config dir:    ${OVERLEAF_DIR}"
  echo ""
  echo "  First-time setup:"
  echo "  1. Open http://localhost:${OVERLEAF_PORT}"
  echo "  2. Create an admin account (first registered user becomes admin)"
  echo ""
  echo "  Shell helpers:"
  echo "    overleaf-ps       - container status"
  echo "    overleaf-logs     - tail logs"
  echo "    overleaf-shell    - bash into sharelatex container"
  echo "    overleaf-restart  - restart services"
  echo "    overleaf-update   - pull and restart"
  echo "    overleaf-down     - stop services"
}

install_overleaf
