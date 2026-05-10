# Shared API key configuration library
# Source this from any module: source "${SCRIPT_DIR}/../lib/api.sh"

API_KEYS_DIR="${HOME}/.config/rinbarpen"
API_KEYS_FILE="${API_KEYS_DIR}/api-keys.env"

# Load keys from shared config if available
if [[ -f "$API_KEYS_FILE" ]]; then
  source "$API_KEYS_FILE"
fi

# Prompt for a key if not already set, optionally save to shared config
# Usage: BRAVE_API_KEY=$(api_key_get "BRAVE_API_KEY" "Brave API key" true)
#   $1 = env var name
#   $2 = display label for prompt
#   $3 = "true" for secret input (-s), anything else for visible
api_key_get() {
  local name="$1" label="$2" secret="${3:-false}"
  local val="${!name:-}"
  if [[ -z "$val" ]]; then
    if [[ "$secret" == "true" ]]; then
      read -r -s -p "${label}: " val; echo ""
    else
      read -r -p "${label}: " val
    fi
    if [[ -n "$val" ]]; then
      api_key_set "$name" "$val"
    fi
  fi
  echo "$val"
}

# Save a key to the shared config file
api_key_set() {
  local name="$1" val="$2"
  mkdir -p "$API_KEYS_DIR"
  if grep -q "^export ${name}=" "$API_KEYS_FILE" 2>/dev/null; then
    sed -i "s|^export ${name}=.*|export ${name}=$(printf '%s\n' "$val" | sed 's/[&/\]/\\&/g')|" "$API_KEYS_FILE"
  else
    echo "export ${name}=${val}" >> "$API_KEYS_FILE"
  fi
}

# Print a masked version of a key for display
api_key_mask() {
  local val="$1"
  if [[ ${#val} -le 8 ]]; then
    echo "****"
  else
    echo "${val:0:4}...${val: -4}"
  fi
}

# List all configured keys (masked values)
api_key_list() {
  if [[ ! -f "$API_KEYS_FILE" ]]; then
    echo "No API keys configured yet."
    return
  fi
  echo "Configured API keys (${API_KEYS_FILE}):"
  while IFS='=' read -r name val; do
    name="${name#export }"
    val="${val#\"}"; val="${val%\"}"
    if [[ -n "$val" ]]; then
      printf "  %-25s %s\n" "$name" "$(api_key_mask "$val")"
    fi
  done < "$API_KEYS_FILE"
}

# Interactively prompt for a single key
api_key_interactive() {
  local name="$1" label="$2" secret="${3:-false}"
  local current="${!name:-}"
  if [[ -n "$current" ]]; then
    echo "Current ${name}: $(api_key_mask "$current")"
  fi
  local val
  if [[ "$secret" == "true" ]]; then
    read -r -s -p "${label}: " val; echo ""
  else
    read -r -p "${label}: " val
  fi
  if [[ -n "$val" ]]; then
    api_key_set "$name" "$val"
    log_info "${name} saved"
  else
    log_info "${name} skipped"
  fi
}
