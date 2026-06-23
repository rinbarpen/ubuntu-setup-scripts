#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

DAEMON_JSON="/etc/docker/daemon.json"

need_cmd docker

# Check if Docker daemon is running
if ! sudo systemctl is-active --quiet docker 2>/dev/null; then
  log_warn "Docker daemon is not running — start it with: sudo systemctl start docker"
  if ! confirm "Start Docker now?"; then
    log_info "docker-config: skipped (Docker not running)"
    exit 0
  fi
  sudo systemctl start docker
fi

# Show current mirror configuration (if any)
if [[ -f "$DAEMON_JSON" ]]; then
  _current_mirrors=$(python3 -c "
import json
try:
    for m in json.load(open('$DAEMON_JSON')).get('registry-mirrors', []):
        print(f'  - {m}')
except: pass
" 2>/dev/null)
  if [[ -n "$_current_mirrors" ]]; then
    log_info "Currently configured registry mirrors:"
    echo "$_current_mirrors"
  fi
fi

if ! confirm "Configure Docker registry mirrors?"; then
  log_info "docker-config: skipped"
  exit 0
fi

declare -a MIRRORS=()

if command -v whiptail &>/dev/null; then
  CHOICES=$(whiptail --title "Docker Registry Mirrors" --checklist \
    "Select registry mirrors (SPACE to toggle, ENTER to confirm):" 20 72 8 \
    "dockerproxy" "https://dockerproxy.cn"                 ON  \
    "one-ms"      "https://docker.1ms.run"                 ON  \
    "xuanyuan"    "https://docker.xuanyuan.me"             ON  \
    "netease"     "https://hub-mirror.c.163.com"           OFF \
    "baidu"       "https://mirror.baidubce.com"            OFF \
    "tencent"     "https://ccr.ccs.tencentyun.com"         OFF \
    "aliyun"      "Aliyun (需要输入实例 ID)"                OFF \
    "custom"      "自定义镜像 URL"                          OFF \
    3>&1 1>&2 2>&3) || CHOICES=""

  SELECTED=$(echo "$CHOICES" | tr -d '"')

  for item in $SELECTED; do
    case "$item" in
      dockerproxy) MIRRORS+=("https://dockerproxy.cn") ;;
      one-ms)      MIRRORS+=("https://docker.1ms.run") ;;
      xuanyuan)    MIRRORS+=("https://docker.xuanyuan.me") ;;
      netease)     MIRRORS+=("https://hub-mirror.c.163.com") ;;
      baidu)       MIRRORS+=("https://mirror.baidubce.com") ;;
      tencent)     MIRRORS+=("https://ccr.ccs.tencentyun.com") ;;
      aliyun)
        read -r -p "Aliyun 容器镜像服务实例 ID (https://cr.console.aliyun.com 获取): " ALIYUN_ID
        [[ -n "$ALIYUN_ID" ]] && MIRRORS+=("https://${ALIYUN_ID}.mirror.aliyuncs.com")
        ;;
      custom) ;;
    esac
  done

  # Handle custom mirrors separately (after known mirrors)
  if echo "$SELECTED" | grep -Fqw "custom"; then
    read -r -p "自定义镜像 URL（空格分隔，如 https://mirror1.example.com https://mirror2.example.com）: " CUSTOM_MIRRORS
    for url in $CUSTOM_MIRRORS; do
      MIRRORS+=("$url")
    done
  fi
else
  # Fallback: text-only input
  log_info "whiptail not available — using text input"
  read -r -p "Docker registry mirror URL(s) (space-separated, leave blank to skip): " MIRROR_INPUT
  for url in $MIRROR_INPUT; do
    MIRRORS+=("$url")
  done
fi

if [[ ${#MIRRORS[@]} -eq 0 ]]; then
  log_info "No mirrors selected, clearing mirror list"
fi

# Merge / write daemon.json via python3 (preserves existing non-mirror keys)
PY_CONTENT=$(python3 - "$DAEMON_JSON" "${MIRRORS[@]}" << 'PYEOF'
import json, os, sys

path = sys.argv[1]
new_mirrors = sys.argv[2:] if len(sys.argv) > 2 else []

try:
    with open(path) as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    cfg = {}

old_mirrors = cfg.get("registry-mirrors", [])

if old_mirrors == new_mirrors and os.path.exists(path):
    print("__UNCHANGED__")
    sys.exit(0)

cfg["registry-mirrors"] = new_mirrors
print(json.dumps(cfg, indent=2))
PYEOF
)

if [[ "$PY_CONTENT" == "__UNCHANGED__" ]]; then
  log_info "Mirror configuration unchanged, skipping restart"
else
  echo "$PY_CONTENT" | sudo tee "$DAEMON_JSON" > /dev/null
  log_info "daemon.json written to $DAEMON_JSON"

  log_info "Restarting Docker daemon..."
  sudo systemctl restart docker

  # Verify
  log_info "Verifying registry mirrors..."
  if docker info 2>/dev/null | grep -A5 "Registry Mirrors"; then
    log_info "Docker mirrors configured successfully"
  else
    log_warn "Could not verify mirrors. Check $DAEMON_JSON manually."
  fi
fi

log_info "docker-config: done"
