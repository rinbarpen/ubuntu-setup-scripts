#!/usr/bin/env bash
set -euo pipefail

RINBAKE_DIR="$(cd "$(dirname "$0")" && pwd)"
CMD_NAME="rinbake"
TARGET_DIR="${HOME}/.local/bin"
TARGET="${TARGET_DIR}/${CMD_NAME}"
SOURCE="${RINBAKE_DIR}/src/index.ts"

if ! command -v bun &>/dev/null; then
  echo "[ERR] bun 未安装，请先安装 bun: curl -fsSL https://bun.sh/install | bash" >&2
  exit 1
fi

echo "[INFO] 安装依赖..."
bun install --cwd "${RINBAKE_DIR}" --frozen-lockfile 2>/dev/null || bun install --cwd "${RINBAKE_DIR}"

echo "[INFO] 注册 bun link..."
bun link --cwd "${RINBAKE_DIR}" 2>/dev/null || true

mkdir -p "${TARGET_DIR}"

cat > "${TARGET}" << WRAPPER
#!/usr/bin/env bash
exec bun "${SOURCE}" "\$@"
WRAPPER

chmod +x "${TARGET}"

echo "[OK] 安装完成！现在可以直接运行: ${CMD_NAME} help"
echo "    (如果 ${TARGET_DIR} 不在 PATH 中，请将其加入 ~/.zshrc 或 ~/.bashrc)"
