#!/usr/bin/env bash
set -euo pipefail

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
BACKUP_DIR="$HOME/.claude/backups"

declare -A PROVIDER_URL
declare -A PROVIDER_MODELS
declare -A PROVIDER_KEY

PROVIDER_URL["deepseek"]="https://api.deepseek.com/anthropic"
PROVIDER_MODELS["deepseek"]="deepseek-v4-pro deepseek-v4-flash"
PROVIDER_KEY["deepseek"]="ANTHROPIC_AUTH_TOKEN"

PROVIDER_URL["qwen"]="https://dashscope-intl.aliyuncs.com/apps/anthropic"
PROVIDER_MODELS["qwen"]="qwen3.6-plus qwen3-max qwen3-coder-plus"
PROVIDER_KEY["qwen"]="ANTHROPIC_AUTH_TOKEN"

PROVIDER_URL["glm"]="https://open.bigmodel.cn/api/anthropic"
PROVIDER_MODELS["glm"]="glm-5 glm-4.7"
PROVIDER_KEY["glm"]="ANTHROPIC_AUTH_TOKEN"

PROVIDER_URL["minimax"]="https://api.minimaxi.com/anthropic"
PROVIDER_MODELS["minimax"]="MiniMax-M2.7 MiniMax-M2.5"
PROVIDER_KEY["minimax"]="ANTHROPIC_AUTH_TOKEN"

PROVIDER_URL["aixor"]="https://aixor.org"
PROVIDER_MODELS["aixor"]="deepseek-v4-pro qwen3.6-plus glm-5 gpt-4o"
PROVIDER_KEY["aixor"]="ANTHROPIC_AUTH_TOKEN"

print_header() {
  echo "========================================"
  echo "  Claude Code 模型切换工具"
  echo "========================================"
}

print_usage() {
  echo "用法: $0 <command> [options]"
  echo ""
  echo "命令:"
  echo "  list              列出所有支持的提供商"
  echo "  switch <p> [model] 切换到指定提供商"
  echo "  status            显示当前配置"
  echo "  backup            备份配置"
  echo ""
  echo "示例:"
  echo "  $0 switch deepseek v4-pro"
  echo "  $0 switch aixor deepseek-v4-pro"
  echo "  $0 list"
}

backup_settings() {
  mkdir -p "$BACKUP_DIR"
  local ts=$(date +%Y%m%d_%H%M%S)
  local bf="$BACKUP_DIR/settings.json.backup.$ts"
  if [[ -f "$CLAUDE_SETTINGS" ]]; then
    cp "$CLAUDE_SETTINGS" "$bf"
    echo "已备份到: $bf"
  fi
}

get_provider() {
  [[ ! -f "$CLAUDE_SETTINGS" ]] && echo "unknown" && return
  local url=$(grep -o '"ANTHROPIC_BASE_URL":[[:space:]]*"[^"]*"' "$CLAUDE_SETTINGS" 2>/dev/null | grep -o 'https://[^"]*' || echo "")
  case "$url" in
    *deepseek*) echo "deepseek" ;;
    *dashscope*|*aliyuncs*) echo "qwen" ;;
    *bigmodel*) echo "glm" ;;
    *minimaxi*) echo "minimax" ;;
    *aixor*) echo "aixor" ;;
    *) echo "unknown" ;;
  esac
}

print_status() {
  echo ""
  echo "--- 当前配置 ---"
  [[ ! -f "$CLAUDE_SETTINGS" ]] && echo "未找到配置文件" && return
  local p=$(get_provider)
  local m=$(grep -o '"ANTHROPIC_MODEL":[[:space:]]*"[^"]*"' "$CLAUDE_SETTINGS" 2>/dev/null | grep -o '"[^"]*"$' | tr -d '"' || echo "unknown")
  echo "提供商: $p"
  echo "模型: $m"
}

list_providers() {
  echo ""
  echo "支持的提供商 (2026年4月最新):"
  echo ""
  for p in deepseek qwen glm minimax aixor; do
    echo "★ $p"
    echo "  URL: ${PROVIDER_URL[$p]}"
    echo "  模型: ${PROVIDER_MODELS[$p]}"
    echo ""
  done
}

switch_model() {
  local provider="$1"
  local model="${2:-}"
  
  if [[ -z "${PROVIDER_MODELS[$provider]:-}" ]]; then
    echo "错误: 未知提供商 '$provider'"
    echo "支持: deepseek, qwen, glm, minimax, aixor"
    exit 1
  fi
  
  if [[ -z "$model" ]]; then
    model=$(echo "${PROVIDER_MODELS[$provider]}" | awk '{print $1}')
    echo "使用默认模型: $model"
  fi
  
  if [[ ! " ${PROVIDER_MODELS[$provider]} " =~ " $model " ]]; then
    echo "错误: 模型 '$model' 无效"
    echo "可用: ${PROVIDER_MODELS[$provider]}"
    exit 1
  fi
  
  backup_settings
  
  local key="${PROVIDER_KEY[$provider]}"
  local token=""
  if [[ -f "$CLAUDE_SETTINGS" ]]; then
    token=$(grep -o "\"$key\":[[:space:]]*\"[^\"]*\"" "$CLAUDE_SETTINGS" 2>/dev/null | grep -o '"[^"]*"$' | tr -d '"' || echo "")
  fi
  
  if [[ -z "$token" ]]; then
    echo "请输入 API Token:"
    read -r token
  fi
  
  local max_tokens="8192"
  [[ "$model" == *"coder"* ]] && max_tokens="16384"
  [[ "$model" == *"max"* ]] && max_tokens="32768"
  
  cat > "$CLAUDE_SETTINGS" << ENDJSON
{
  "env": {
    "$key": "$token",
    "ANTHROPIC_BASE_URL": "${PROVIDER_URL[$provider]}",
    "ANTHROPIC_MODEL": "$model",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "$model",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "$model",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "$model",
    "CLAUDE_CODE_SUBAGENT_MODEL": "$model",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "$max_tokens"
  }
}
ENDJSON
  
  echo ""
  echo "配置已更新: $provider / $model"
  echo "重启 Claude Code 生效"
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    list)
      print_header
      list_providers
      ;;
    switch)
      [[ $# -lt 2 ]] && echo "用法: $0 switch <provider> [model]" && exit 1
      print_header
      switch_model "$2" "${3:-}"
      ;;
    status)
      print_header
      print_status
      ;;
    backup)
      print_header
      backup_settings
      ;;
    help|--help|-h)
      print_usage
      ;;
    *)
      print_header
      print_status
      echo ""
      print_usage
      ;;
  esac
}

main "$@"
