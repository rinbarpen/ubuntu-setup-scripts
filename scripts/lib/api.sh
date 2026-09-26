#!/usr/bin/env bash
# Shared API-key compatibility layer for standalone shell modules.

API_KEYS_DIR="${HOME}/.config/rinbarpen"
API_KEYS_FILE="${API_KEYS_DIR}/api-keys.env"

if [[ -f "$API_KEYS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$API_KEYS_FILE"
fi

api_key_get() {
  local name="$1" label="$2" secret="${3:-false}"
  local val="${!name:-}"
  if [[ -z "$val" ]]; then
    if [[ "$secret" == "true" ]]; then
      read -r -s -p "${label}: " val; echo ""
    else
      read -r -p "${label}: " val
    fi
    [[ -n "$val" ]] && api_key_set "$name" "$val"
  fi
  echo "$val"
}

api_key_set() {
  local name="$1" val="$2"
  mkdir -p "$API_KEYS_DIR"
  if grep -q "^export ${name}=" "$API_KEYS_FILE" 2>/dev/null; then
    sed -i "s|^export ${name}=.*|export ${name}=$(printf '%s\n' "$val" | sed 's/[&/\\]/\\&/g')|" "$API_KEYS_FILE"
  else
    echo "export ${name}=${val}" >> "$API_KEYS_FILE"
  fi
}
