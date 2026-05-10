#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/api.sh"

# Standalone API key configuration tool.
# Usage:
#   bash api-config.sh           — interactive whiptail checklist
#   bash api-config.sh --list    — list configured keys (masked)
#   bash api-config.sh --show    — show all keys in plaintext
#   bash api-config.sh --set KEY VALUE — set a single key non-interactively

if [[ $# -gt 0 ]]; then
  case "$1" in
    --list|-l)
      api_key_list
      exit 0
      ;;
    --show|-s)
      if [[ ! -f "$API_KEYS_FILE" ]]; then
        echo "No API keys configured yet."
        exit 0
      fi
      echo "API keys (${API_KEYS_FILE}):"
      cat "$API_KEYS_FILE"
      exit 0
      ;;
    --set)
      if [[ $# -lt 3 ]]; then
        log_err "Usage: $0 --set KEY VALUE"
        exit 1
      fi
      api_key_set "$2" "$3"
      log_info "$2 saved"
      exit 0
      ;;
    *)
      log_err "Unknown option: $1"
      echo "Usage: $0 [--list|--show|--set KEY VALUE]"
      exit 1
      ;;
  esac
fi

# Interactive mode
if command -v whiptail &>/dev/null; then
  # Build description with current status
  _desc_brave="Brave Search API key"
  _desc_github="GitHub Personal Access Token"
  _desc_openai="OpenAI API key (also for compatible endpoints)"
  _desc_anthropic="Anthropic API key"
  _desc_deepseek="DeepSeek API key"
  _desc_postgres="PostgreSQL connection string (DSN)"
  _desc_zerotier="ZeroTier network ID"
  _desc_proxy="HTTP proxy address"

  [[ -n "${BRAVE_API_KEY:-}" ]]    && _desc_brave="${_desc_brave} [✓]"
  [[ -n "${GITHUB_TOKEN:-}" ]]     && _desc_github="${_desc_github} [✓]"
  [[ -n "${OPENAI_API_KEY:-}" ]]   && _desc_openai="${_desc_openai} [✓]"
  [[ -n "${ANTHROPIC_API_KEY:-}" ]] && _desc_anthropic="${_desc_anthropic} [✓]"
  [[ -n "${DEEPSEEK_API_KEY:-}" ]] && _desc_deepseek="${_desc_deepseek} [✓]"
  [[ -n "${POSTGRES_DSN:-}" ]]     && _desc_postgres="${_desc_postgres} [✓]"
  [[ -n "${ZEROTIER_NETWORK_ID:-}" ]] && _desc_zerotier="${_desc_zerotier} [✓]"
  [[ -n "${PROXY_ADDR:-}" ]]       && _desc_proxy="${_desc_proxy} [✓]"

  CHOICES=$(whiptail --title "API Configuration" --checklist \
    "Select API keys to configure (SPACE to toggle, ENTER to confirm):" 20 65 8 \
    "BRAVE_API_KEY"      "${_desc_brave}"      ON  \
    "GITHUB_TOKEN"       "${_desc_github}"      ON  \
    "OPENAI_API_KEY"     "${_desc_openai}"       ON  \
    "ANTHROPIC_API_KEY"  "${_desc_anthropic}"    ON  \
    "DEEPSEEK_API_KEY"   "${_desc_deepseek}"     ON  \
    "POSTGRES_DSN"       "${_desc_postgres}"     OFF \
    "ZEROTIER_NETWORK_ID" "${_desc_zerotier}"    OFF \
    "PROXY_ADDR"         "${_desc_proxy}"        OFF \
    3>&1 1>&2 2>&3) || { log_warn "Cancelled."; exit 0; }

  SELECTED=$(echo "$CHOICES" | tr -d '"')

  for _key in $SELECTED; do
    case "$_key" in
      BRAVE_API_KEY)
        api_key_interactive "BRAVE_API_KEY" "Brave API key" true
        ;;
      GITHUB_TOKEN)
        api_key_interactive "GITHUB_TOKEN" "GitHub Personal Access Token" true
        ;;
      OPENAI_API_KEY)
        api_key_interactive "OPENAI_API_KEY" "OpenAI API key" true
        ;;
      ANTHROPIC_API_KEY)
        api_key_interactive "ANTHROPIC_API_KEY" "Anthropic API key" true
        ;;
      DEEPSEEK_API_KEY)
        api_key_interactive "DEEPSEEK_API_KEY" "DeepSeek API key" true
        ;;
      POSTGRES_DSN)
        api_key_interactive "POSTGRES_DSN" "Postgres DSN (postgresql://user:pass@host:port/db)" false
        ;;
      ZEROTIER_NETWORK_ID)
        api_key_interactive "ZEROTIER_NETWORK_ID" "ZeroTier Network ID" false
        ;;
      PROXY_ADDR)
        api_key_interactive "PROXY_ADDR" "HTTP proxy address (e.g. http://127.0.0.1:7890)" false
        ;;
    esac
  done

  echo ""
  log_info "API configuration complete"
  api_key_list
else
  log_warn "whiptail not found — falling back to line-by-line prompts"
  api_key_interactive "BRAVE_API_KEY" "Brave API key" true
  api_key_interactive "GITHUB_TOKEN" "GitHub Personal Access Token" true
  api_key_interactive "OPENAI_API_KEY" "OpenAI API key" true
  api_key_interactive "ANTHROPIC_API_KEY" "Anthropic API key" true
  api_key_interactive "DEEPSEEK_API_KEY" "DeepSeek API key" true
fi
