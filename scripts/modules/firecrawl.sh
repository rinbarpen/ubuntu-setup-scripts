#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

need_cmd docker
need_cmd curl
docker compose version &>/dev/null || { log_err "docker compose plugin not found"; exit 1; }

FIRECRAWL_DIR="${FIRECRAWL_DIR:-${HOME}/.local/share/firecrawl}"
FIRECRAWL_PORT="${FIRECRAWL_PORT:-3002}"

log_info "Firecrawl Docker Compose deployment"

# Prepare directory
mkdir -p "$FIRECRAWL_DIR"

# Download docker-compose.yaml
_COMPOSE_URL="https://raw.githubusercontent.com/firecrawl/firecrawl/main/docker-compose.yaml"
if [[ -f "${FIRECRAWL_DIR}/docker-compose.yaml" ]]; then
  log_info "docker-compose.yaml already exists"
else
  log_info "Downloading docker-compose.yaml..."
  curl -fsSL "$_COMPOSE_URL" -o "${FIRECRAWL_DIR}/docker-compose.yaml" || {
    log_err "Failed to download docker-compose.yaml"
    exit 1
  }
fi

# Create minimal .env
cat > "${FIRECRAWL_DIR}/.env" << ENVEOF
PORT=${FIRECRAWL_PORT}
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=firecrawl
REDIS_URL=redis://redis:6379
LOGGING_LEVEL=info
ENVEOF
log_info "Created ${FIRECRAWL_DIR}/.env"

# Start the stack
log_info "Starting Firecrawl stack (first build may take 10-30 minutes)..."
docker compose -f "${FIRECRAWL_DIR}/docker-compose.yaml" up -d 2>&1 || {
  log_err "docker compose up failed"
  exit 1
}

# Health check
log_info "Waiting for Firecrawl to be ready..."
for _i in $(seq 1 60); do
  if curl -s -o /dev/null "http://localhost:${FIRECRAWL_PORT}/health" 2>/dev/null; then
    log_info "Firecrawl is ready at http://localhost:${FIRECRAWL_PORT}"
    break
  fi
  sleep 5
done

echo ""
log_info "Firecrawl deployment complete"
echo "  URL: http://localhost:${FIRECRAWL_PORT}"
echo "  Config: ${FIRECRAWL_DIR}/.env"
echo "  Compose: ${FIRECRAWL_DIR}/docker-compose.yaml"
echo "  Manage: docker compose -f ${FIRECRAWL_DIR}/docker-compose.yaml {up|down|logs|ps}"
echo ""
log_info "firecrawl: done"
