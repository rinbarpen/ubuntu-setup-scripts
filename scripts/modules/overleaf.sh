#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

need_cmd docker
need_cmd python3
need_cmd curl
# lsof is optional — port conflict check will be skipped if absent

if ! docker compose version &>/dev/null; then
  log_err "docker compose plugin not found — run ubuntu-base module first"
  exit 1
fi

install_overleaf() {
  OVERLEAF_DIR="${HOME}/overleaf"
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
  OVERLEAF_SITE_URL="${OVERLEAF_SITE_URL:-http://0.0.0.0:25681}"
  OVERLEAF_APP_NAME="${OVERLEAF_APP_NAME:-Overleaf @Rczx}"
  OVERLEAF_PORT="${OVERLEAF_PORT:-25681}"
  OVERLEAF_MONGO_INTERNAL="${OVERLEAF_MONGO_INTERNAL:-true}"
  OVERLEAF_MONGO_URL="${OVERLEAF_MONGO_URL:-mongodb://mongo/sharelatex_data}"
  OVERLEAF_EMAIL="${OVERLEAF_EMAIL:-}"
  OVERLEAF_SMTP_ENABLE="${OVERLEAF_SMTP_ENABLE:-false}"
  OVERLEAF_SMTP_HOST="${OVERLEAF_SMTP_HOST:-}"
  OVERLEAF_SMTP_PORT="${OVERLEAF_SMTP_PORT:-587}"
  OVERLEAF_SMTP_USER="${OVERLEAF_SMTP_USER:-}"
  OVERLEAF_SMTP_PASS="${OVERLEAF_SMTP_PASS:-}"
  OVERLEAF_SMTP_SECURE="${OVERLEAF_SMTP_SECURE:-false}"
  OVERLEAF_SMTP_FROM="${OVERLEAF_SMTP_FROM:-}"
  OVERLEAF_INSTALL_TEXLIVE="${OVERLEAF_INSTALL_TEXLIVE:-false}"
  OVERLEAF_INSTALL_CJK="${OVERLEAF_INSTALL_CJK:-false}"
  OVERLEAF_INSTALL_XELATEX="${OVERLEAF_INSTALL_XELATEX:-false}"
  OVERLEAF_COMMIT_CUSTOM="${OVERLEAF_COMMIT_CUSTOM:-false}"
  OVERLEAF_IMAGE="${OVERLEAF_IMAGE:-sharelatex/sharelatex:latest}"

  # ── Whiptail prompts ────────────────────────────────────────────────────
  if command -v whiptail &>/dev/null; then
    whiptail --msgbox "Overleaf (ShareLaTeX Community Edition) self-hosted setup.

This will deploy ShareLaTeX via Docker Compose with:
  - ShareLaTeX web app + Redis (always)
  - MongoDB companion container (optional, or external DB)
  - Optional: TeX Live, CJK fonts, XeLaTeX

Requirements: Docker + docker compose plugin." 14 60

    # MongoDB mode
    _mongo_choice=$(whiptail --title "MongoDB" --menu "MongoDB configuration:" 14 60 2 \
        "internal" "Run MongoDB as companion container (fully self-contained)" \
        "external" "Use an external MongoDB connection URL" \
        3>&1 1>&2 2>&3) || _mongo_choice=""
    case "$_mongo_choice" in
      internal)
        OVERLEAF_MONGO_INTERNAL="true"
        OVERLEAF_MONGO_URL="mongodb://mongo/sharelatex_data"
        ;;
      external)
        OVERLEAF_MONGO_INTERNAL="false"
        OVERLEAF_MONGO_URL=""
        while [[ -z "$OVERLEAF_MONGO_URL" ]]; do
          read -r -p "MongoDB connection URL (mongodb://...): " OVERLEAF_MONGO_URL
        done
        ;;
    esac
  fi

  # Non-whiptail MongoDB fallback
  if [[ ! -v _mongo_choice ]] && ! command -v whiptail &>/dev/null; then
    echo "MongoDB mode: internal (companion container) or external (existing server)?"
    read -r -p "Choice [internal]: " _mongo_fb
    case "${_mongo_fb,,}" in
      external)
        OVERLEAF_MONGO_INTERNAL="false"
        OVERLEAF_MONGO_URL=""
        while [[ -z "$OVERLEAF_MONGO_URL" ]]; do
          read -r -p "MongoDB connection URL (mongodb://...): " OVERLEAF_MONGO_URL
        done
        ;;
      *) ;;  # keep default (internal)
    esac
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

  # Data directory
  read -r -p "Data directory [${OVERLEAF_DIR}]: " _dir_input
  [[ -n "$_dir_input" ]] && OVERLEAF_DIR="$_dir_input"
  OVERLEAF_COMPOSE="${OVERLEAF_DIR}/docker-compose.yml"
  OVERLEAF_ENV="${OVERLEAF_DIR}/.env"

  # Admin email
  read -r -p "Admin email (optional): " _email_input
  [[ -n "$_email_input" ]] && OVERLEAF_EMAIL="$_email_input"

  # SMTP
  if confirm "Configure SMTP for email notifications?"; then
    OVERLEAF_SMTP_ENABLE="true"
    read -r -p "SMTP host: " OVERLEAF_SMTP_HOST
    read -r -p "SMTP port [${OVERLEAF_SMTP_PORT}]: " _smtp_port
    [[ -n "$_smtp_port" ]] && OVERLEAF_SMTP_PORT="$_smtp_port"
    read -r -p "SMTP user: " OVERLEAF_SMTP_USER
    read -r -s -p "SMTP password: " OVERLEAF_SMTP_PASS; echo ""
    confirm "Use TLS (SMTP secure)?" && OVERLEAF_SMTP_SECURE="true" || OVERLEAF_SMTP_SECURE="false"
    read -r -p "SMTP from address: " OVERLEAF_SMTP_FROM
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

  # ── Create directories ──────────────────────────────────────────────────
  mkdir -p "$OVERLEAF_DIR"
  mkdir -p "$OVERLEAF_DIR/data" "$OVERLEAF_DIR/texlive" "$OVERLEAF_DIR/fonts" "$OVERLEAF_DIR/redis"
  if [[ "$OVERLEAF_MONGO_INTERNAL" == "true" ]]; then
    mkdir -p "$OVERLEAF_DIR/mongo"
  fi

  # ── Export for Python3 heredocs ─────────────────────────────────────────
  export OVERLEAF_DIR OVERLEAF_SITE_URL OVERLEAF_APP_NAME OVERLEAF_PORT
  export OVERLEAF_MONGO_INTERNAL OVERLEAF_MONGO_URL OVERLEAF_EMAIL
  export OVERLEAF_SMTP_ENABLE OVERLEAF_SMTP_HOST OVERLEAF_SMTP_PORT
  export OVERLEAF_SMTP_USER OVERLEAF_SMTP_PASS OVERLEAF_SMTP_SECURE OVERLEAF_SMTP_FROM
  export OVERLEAF_IMAGE

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
    "OVERLEAF_APP_NAME": os.environ.get("OVERLEAF_APP_NAME", "Overleaf"),
    "OVERLEAF_PORT": os.environ.get("OVERLEAF_PORT", "25681"),
    "OVERLEAF_MONGO_INTERNAL": os.environ.get("OVERLEAF_MONGO_INTERNAL", "true"),
    "OVERLEAF_MONGO_URL": os.environ.get("OVERLEAF_MONGO_URL", "mongodb://mongo/sharelatex_data"),
    "OVERLEAF_EMAIL": os.environ.get("OVERLEAF_EMAIL", ""),
    "OVERLEAF_SMTP_ENABLE": os.environ.get("OVERLEAF_SMTP_ENABLE", "false"),
    "OVERLEAF_SMTP_HOST": os.environ.get("OVERLEAF_SMTP_HOST", ""),
    "OVERLEAF_SMTP_PORT": os.environ.get("OVERLEAF_SMTP_PORT", "587"),
    "OVERLEAF_SMTP_USER": os.environ.get("OVERLEAF_SMTP_USER", ""),
    "OVERLEAF_SMTP_PASS": os.environ.get("OVERLEAF_SMTP_PASS", ""),
    "OVERLEAF_SMTP_SECURE": os.environ.get("OVERLEAF_SMTP_SECURE", "false"),
    "OVERLEAF_SMTP_FROM": os.environ.get("OVERLEAF_SMTP_FROM", ""),
    "OVERLEAF_IMAGE": os.environ.get("OVERLEAF_IMAGE", "sharelatex/sharelatex:latest"),
}

lines = []
for key, val in env.items():
    lines.append(f"{key}={q(val)}\n")

path.write_text("".join(lines))
PYEOF
  log_info ".env written to $OVERLEAF_ENV"
  chmod 600 "$OVERLEAF_ENV"

  # ── Write docker-compose.yml ────────────────────────────────────────────
  python3 - "$OVERLEAF_COMPOSE" << 'PYEOF'
import os, pathlib, sys, json

path = pathlib.Path(sys.argv[1])

site_url   = os.environ.get("OVERLEAF_SITE_URL", "http://0.0.0.0:25681")
app_name   = os.environ.get("OVERLEAF_APP_NAME", "Overleaf")
port       = os.environ.get("OVERLEAF_PORT", "25681")
mongo_url  = os.environ.get("OVERLEAF_MONGO_URL", "mongodb://mongo/sharelatex_data")
email_addr = os.environ.get("OVERLEAF_EMAIL", "")
mongo_internal = os.environ.get("OVERLEAF_MONGO_INTERNAL", "true") == "true"
image      = os.environ.get("OVERLEAF_IMAGE", "sharelatex/sharelatex:latest")

smtp_enable = os.environ.get("OVERLEAF_SMTP_ENABLE", "false") == "true"
smtp_host   = os.environ.get("OVERLEAF_SMTP_HOST", "")
smtp_port   = os.environ.get("OVERLEAF_SMTP_PORT", "587")
smtp_user   = os.environ.get("OVERLEAF_SMTP_USER", "")
smtp_pass   = os.environ.get("OVERLEAF_SMTP_PASS", "")
smtp_secure = os.environ.get("OVERLEAF_SMTP_SECURE", "false") == "true"
smtp_from   = os.environ.get("OVERLEAF_SMTP_FROM", "")

volumes = {
    "data":   {"driver": "local"},
    "texlive":{"driver": "local"},
    "fonts":  {"driver": "local"},
    "redis":  {"driver": "local"},
}

if mongo_internal:
    volumes["mongo"] = {"driver": "local"}

services = {}

# ── sharelatex service ──
sharelatex_env = [
    f"SHARELATEX_APP_NAME={app_name}",
    f"SHARELATEX_SITE_URL={site_url}",
    f"SHARELATEX_NAV_TITLE={app_name}",
    "SHARELATEX_LEFT_FOOTER=",
    "SHARELATEX_RIGHT_FOOTER=",
    "SHARELATEX_RICHTAGS=true",
    "SHARELATEX_EMAIL_CONFIRMATION_DISABLED=true",
    f"MONGO_URL={mongo_url}",
    "REDIS_HOST=redis",
    "REDIS_PORT=6379",
]

if email_addr:
    sharelatex_env.append(f"SHARELATEX_ADMIN_EMAIL={email_addr}")

if smtp_enable and smtp_host:
    sharelatex_env.append("SHARELATEX_EMAIL_CONFIRMATION_DISABLED=false")
    sharelatex_env.append(f"SHARELATEX_EMAIL_HOST={smtp_host}")
    sharelatex_env.append(f"SHARELATEX_EMAIL_PORT={smtp_port}")
    if smtp_user:
        sharelatex_env.append(f"SHARELATEX_EMAIL_USER={smtp_user}")
    if smtp_pass:
        sharelatex_env.append(f"SHARELATEX_EMAIL_PASS={smtp_pass}")
    sharelatex_env.append(f"SHARELATEX_EMAIL_SECURE={'true' if smtp_secure else 'false'}")
    if smtp_from:
        sharelatex_env.append(f"SHARELATEX_EMAIL_FROM_ADDRESS={smtp_from}")

sharelatex_depends = ["redis"]
if mongo_internal:
    sharelatex_depends.append("mongo")

services["sharelatex"] = {
    "image": image,
    "container_name": "overleaf",
    "depends_on": sharelatex_depends,
    "ports": [f"{port}:80"],
    "volumes": [
        "data:/var/lib/sharelatex",
        "texlive:/usr/local/texlive",
        "fonts:/usr/share/fonts",
    ],
    "environment": sharelatex_env,
    "restart": "always",
}

# ── redis service ──
services["redis"] = {
    "image": "redis:7-alpine",
    "container_name": "overleaf-redis",
    "restart": "always",
    "volumes": ["redis:/data"],
    "command": "redis-server --appendonly yes",
}

# ── mongo service (optional) ──
if mongo_internal:
    services["mongo"] = {
        "image": "mongo:6",
        "container_name": "overleaf-mongo",
        "restart": "always",
        "volumes": ["mongo:/data/db"],
    }

compose = {
    "services": services,
    "volumes": volumes,
}

path.write_text(json.dumps(compose, indent=2) + "\n")
PYEOF
  log_info "docker-compose.yml written to $OVERLEAF_COMPOSE"

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

      # Regenerate compose with new image
      python3 - "$OVERLEAF_COMPOSE" << 'PYEOF2'
import os, pathlib, sys, json
path = pathlib.Path(sys.argv[1])
compose = json.loads(path.read_text())
compose["services"]["sharelatex"]["image"] = "overleaf-custom:latest"
path.write_text(json.dumps(compose, indent=2) + "\n")
PYEOF2

      log_info "Compose file updated to use overleaf-custom:latest"
    fi
  fi

  # ── Shell integration ───────────────────────────────────────────────────
  FISH_FUNC_DIR="$HOME/.config/fish/functions"
  mkdir -p "$FISH_FUNC_DIR"

  cat > "${FISH_FUNC_DIR}/overleaf.fish" << 'FISHEOF'
function overleaf-compose
    docker compose -f $HOME/overleaf/docker-compose.yml $argv
end

function overleaf-logs
    overleaf-compose logs -f $argv
end

function overleaf-restart
    overleaf-compose restart $argv
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
    cat >> "$HOME/.bashrc" << 'BASHEOF'

# overleaf (added by setup)
OVERLEAF_COMPOSE="$HOME/overleaf/docker-compose.yml"
overleaf-compose() { docker compose -f "$OVERLEAF_COMPOSE" "$@"; }
overleaf-logs()    { overleaf-compose logs -f "$@"; }
overleaf-restart() { overleaf-compose restart "$@"; }
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
