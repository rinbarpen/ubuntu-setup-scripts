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

install_deps() {
  bun install --cwd "${RINBAKE_DIR}" "$@"
}

if ! install_deps --frozen-lockfile; then
  # bun >=1.4 在 node_modules/.bin 已有同名链接时会以 EEXIST 失败
  echo "[WARN] 清理残留的 node_modules/.bin 后重试..."
  rm -rf "${RINBAKE_DIR}/node_modules/.bin"
  install_deps || {
    echo "[ERR] 依赖安装失败" >&2
    exit 1
  }
fi

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
