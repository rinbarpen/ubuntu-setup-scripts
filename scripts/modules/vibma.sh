#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

need_cmd npm
need_cmd curl
need_cmd unzip
need_cmd lsof
need_cmd python3

VIBMA_CHANNEL="vibma"
DEFAULT_PORT=3055
PORT="$DEFAULT_PORT"

resolve_port() {
  local pid
  pid="$(lsof -ti :"${DEFAULT_PORT}" || true)"
  if [[ -z "$pid" ]]; then
    PORT="$DEFAULT_PORT"
    return
  fi

  log_warn "Port ${DEFAULT_PORT} is in use by PID(s): ${pid}"
  echo "1) Kill process(es) on ${DEFAULT_PORT} and use it for Vibma"
  echo "2) Use the next available port (3056-3058)"
  read -r -p "Choose [1/2]: " choice

  case "${choice:-2}" in
    1)
      kill ${pid} || true
      sleep 1
      if [[ -n "$(lsof -ti :"${DEFAULT_PORT}" || true)" ]]; then
        log_err "Failed to free port ${DEFAULT_PORT}"
        exit 1
      fi
      PORT="$DEFAULT_PORT"
      ;;
    2|*)
      for candidate in 3056 3057 3058; do
        if [[ -z "$(lsof -ti :"${candidate}" || true)" ]]; then
          PORT="$candidate"
          return
        fi
      done
      log_err "Ports 3055-3058 are all occupied. Free one and re-run."
      exit 1
      ;;
  esac
}

download_plugin() {
  local release_json tag plugin_url base_dir zip_path plugin_dir manifest_path

  release_json="$(curl -fsSL https://api.github.com/repos/ufira-ai/vibma/releases/latest)"
  tag="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])' <<< "$release_json")"
  plugin_url="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(a["browser_download_url"] for a in d["assets"] if a["name"]=="vibma-plugin.zip"))' <<< "$release_json")"

  base_dir="$HOME/.local/share/vibma/releases/${tag}"
  zip_path="${base_dir}/vibma-plugin.zip"
  plugin_dir="${base_dir}/plugin"
  manifest_path="${plugin_dir}/manifest.json"

  mkdir -p "$base_dir"
  log_info "Downloading vibma-plugin.zip (${tag})..."
  curl -fL "$plugin_url" -o "$zip_path"

  rm -rf "$plugin_dir"
  mkdir -p "$plugin_dir"
  unzip -q -o "$zip_path" -d "$plugin_dir"

  if [[ ! -f "$manifest_path" ]]; then
    log_err "manifest.json not found after unzip: ${manifest_path}"
    exit 1
  fi

  log_info "Plugin extracted to: ${plugin_dir}"
  log_info "Use this manifest in Figma: ${manifest_path}"
}

write_claude_settings() {
  local claude_settings="$HOME/.claude/settings.json"
  mkdir -p "$(dirname "$claude_settings")"

  python3 - "$claude_settings" "$PORT" << 'PYEOF'
import json, sys

path = sys.argv[1]
port = sys.argv[2]

try:
    with open(path) as f:
        settings = json.load(f)
except Exception:
    settings = {}

mcp = settings.setdefault("mcpServers", {})
mcp["Vibma"] = {
    "command": "npx",
    "args": ["-y", "@ufira/vibma@latest", "--edit", f"--port={port}"],
}

with open(path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PYEOF

  log_info "Claude MCP server 'Vibma' written to ${claude_settings}"
}

write_codex_settings() {
  local codex_cfg="$HOME/.codex/config.yaml"
  mkdir -p "$(dirname "$codex_cfg")"
  [[ -f "$codex_cfg" ]] || : > "$codex_cfg"

  python3 - "$codex_cfg" "$PORT" << 'PYEOF'
import re
import sys

path = sys.argv[1]
port = sys.argv[2]

with open(path, "r") as f:
    lines = f.readlines()

if not lines:
    lines = []

vibma_block = [
    "  Vibma:\n",
    "    command: npx\n",
    f'    args: ["-y", "@ufira/vibma@latest", "--edit", "--port={port}"]\n',
]

def top_level_key(line: str) -> bool:
    return bool(re.match(r"^[A-Za-z0-9_-]+:\s*", line))

def server_key(line: str) -> bool:
    return bool(re.match(r"^  [A-Za-z0-9_.-]+:\s*", line))

mcp_idx = -1
for i, line in enumerate(lines):
    if re.match(r"^mcpServers:\s*$", line):
        mcp_idx = i
        break

if mcp_idx == -1:
    if lines and lines[-1].strip():
        lines.append("\n")
    lines.append("mcpServers:\n")
    lines.extend(vibma_block)
else:
    body_start = mcp_idx + 1
    body_end = len(lines)
    for i in range(body_start, len(lines)):
        if top_level_key(lines[i]):
            body_end = i
            break

    body = lines[body_start:body_end]
    vibma_start = -1
    vibma_end = -1
    for i, line in enumerate(body):
        if re.match(r"^  Vibma:\s*$", line):
            vibma_start = i
            vibma_end = i + 1
            for j in range(i + 1, len(body)):
                if server_key(body[j]):
                    vibma_end = j
                    break
                vibma_end = j + 1
            break

    if vibma_start != -1:
        body = body[:vibma_start] + body[vibma_end:]

    if body and body[-1].strip():
        body.append("\n")
    body.extend(vibma_block)
    lines = lines[:body_start] + body + lines[body_end:]

with open(path, "w") as f:
    f.writelines(lines)
PYEOF

  log_info "Codex MCP server 'Vibma' written to ${codex_cfg}"
}

install_skill_dir() {
  local source_dir="$1"
  local target_base="$2"
  local skill_name
  skill_name="$(basename "$source_dir")"

  mkdir -p "$target_base"
  local target_dir="${target_base}/${skill_name}"

  if [[ -d "$target_dir" ]]; then
    local backup_dir="${target_dir}.bak.$(date +%Y%m%d%H%M%S)"
    mv "$target_dir" "$backup_dir"
    log_warn "Existing skill backed up: ${backup_dir}"
  fi

  cp -R "$source_dir" "$target_dir"
  log_info "Installed skill: ${target_dir}"
}

install_skills() {
  local skills_src="${SCRIPT_DIR}/../skills"
  local cp_skill="${skills_src}/figma-vibma"
  local mac_skill="${skills_src}/figma-start-macos"

  if [[ ! -f "${cp_skill}/SKILL.md" ]]; then
    log_warn "Missing skill template: ${cp_skill}/SKILL.md"
    return
  fi
  if [[ ! -f "${mac_skill}/SKILL.md" ]]; then
    log_warn "Missing skill template: ${mac_skill}/SKILL.md"
    return
  fi

  install_skill_dir "$cp_skill" "$HOME/.claude/skills"
  install_skill_dir "$mac_skill" "$HOME/.claude/skills"
  install_skill_dir "$cp_skill" "$HOME/.codex/skills"
  install_skill_dir "$mac_skill" "$HOME/.codex/skills"
}

resolve_port
download_plugin
write_claude_settings
write_codex_settings
install_skills

log_info "Vibma setup complete."
echo ""
echo "Next steps:"
echo "1) Start tunnel:"
echo "   VIBMA_PORT=${PORT} npx @ufira/vibma-tunnel@latest"
echo "2) In Figma plugin UI, set:"
echo "   Port: ${PORT}"
echo "   Channel: ${VIBMA_CHANNEL}"
echo "3) Restart your AI tools, then run:"
echo "   connection(method: \"create\")"
echo "   connection(method: \"get\")"
