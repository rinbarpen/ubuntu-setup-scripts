# Claude Code 多模型切换工具

## 概述

`model-switch.sh` 是一个用于管理 Claude Code 多模型配置的脚本，支持快速切换不同的 AI 提供商和模型。

## 快速开始

```bash
# 查看帮助
./model-switch.sh help

# 列出所有支持的提供商
./model-switch.sh list

# 查看当前配置
./model-switch.sh status

# 切换到 DeepSeek V4 Pro（最新）
./model-switch.sh switch deepseek v4-pro

# 切换到 Qwen 3.6 Plus
./model-switch.sh switch qwen qwen3.6-plus

# 切换到 GLM-5
./model-switch.sh switch glm glm-5

# 切换到 MiniMax M2.7
./model-switch.sh switch minimax MiniMax-M2.7

# 切换到 AiXor（统一代理）
./model-switch.sh switch aixor deepseek-v4-pro

# 交互式选择（需要 fzf）
./model-switch.sh interactive
```

## 支持的提供商

### 1. DeepSeek（深度求索）
- **最新模型**: `deepseek-v4-pro`, `deepseek-v4-flash`（2026-04-24 发布）
- **Anthropic Base URL**: `https://api.deepseek.com/anthropic`
- **API Key 环境变量**: `ANTHROPIC_AUTH_TOKEN`
- **文档**: https://api-docs.deepseek.com/

⚠️ **注意**: 旧模型 `deepseek-chat` 和 `deepseek-reasoner` 将在 2026-07-24 弃用

### 2. Qwen（通义千问 - 阿里云）
- **推荐模型**: `qwen3.6-plus`, `qwen3-max-2026-01-23`, `qwen3-coder-plus`
- **Anthropic Base URL**: `https://dashscope-intl.aliyuncs.com/apps/anthropic`
- **API Key 环境变量**: `ANTHROPIC_AUTH_TOKEN`
- **文档**: https://www.alibabacloud.com/help/en/model-studio/

### 3. GLM（智谱 AI）
- **推荐模型**: `glm-5`, `glm-4.7`
- **Anthropic Base URL**: `https://open.bigmodel.cn/api/anthropic`
- **API Key 环境变量**: `ANTHROPIC_AUTH_TOKEN`
- **文档**: https://open.bigmodel.cn/dev/api

### 4. MiniMax（稀宇科技）
- **推荐模型**: `MiniMax-M2.7`, `MiniMax-M2.5`
- **Anthropic Base URL**: `https://api.minimaxi.com/anthropic`
- **API Key 环境变量**: `ANTHROPIC_AUTH_TOKEN`
- **文档**: https://platform.minimax.io/document

### 5. OpenAI
- **推荐模型**: `gpt-4o`, `o1-preview`, `o1-mini`
- **API Key 环境变量**: `OPENAI_API_KEY`
- **注意**: OpenAI 不支持 Anthropic 兼容接口，需使用 OpenAI 兼容模式

### 6. AiXor（统一代理服务）
- **支持模型**: `deepseek-v4-pro`, `qwen3.6-plus`, `glm-5`, `gpt-4o` 等
- **Base URL**: `https://aixor.org`
- **API Key 环境变量**: `ANTHROPIC_AUTH_TOKEN`
- **文档**: https://docs.aixor.org/8336478m0
- **特点**: 一个 Key 访问多个底层模型，简化配置

## 配置文件

脚本修改的配置文件：`~/.claude/settings.json`

配置格式：
```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "sk-...",
    "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
    "ANTHROPIC_MODEL": "deepseek-v4-pro",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-v4-pro",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "deepseek-v4-flash",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "deepseek-v4-flash",
    "CLAUDE_CODE_SUBAGENT_MODEL": "deepseek-v4-pro",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "8192"
  }
}
```

## 自动备份

每次切换模型时，脚本会自动备份当前配置到：
```
~/.claude/backups/settings.json.backup.YYYYMMDD_HHMMSS
```

恢复备份：
```bash
./model-switch.sh restore ~/.claude/backups/settings.json.backup.20260502_120000
```

## API Key 管理

### 方式一：交互式输入
切换模型时，如果未找到 API Key，脚本会提示输入：
```bash
$ ./model-switch.sh switch deepseek v4-pro
未找到 ANTHROPIC_AUTH_TOKEN 环境变量
请输入你的 API Token (或以 'env:' 开头从环境变量读取):
> sk-your-key-here
```

### 方式二：从环境变量读取
```bash
$ ./model-switch.sh switch deepseek v4-pro
未找到 ANTHROPIC_AUTH_TOKEN 环境变量
请输入你的 API Token (或以 'env:' 开头从环境变量读取):
> env:DEEPSEEK_API_KEY
```

### 方式三：预先设置环境变量
在 `~/.bashrc` 或 `~/.zshrc` 中设置：
```bash
export ANTHROPIC_AUTH_TOKEN="sk-..."
export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
```

## 安装要求

- **Bash**: 脚本需要 Bash shell
- **fzf** (可选): 用于交互式选择模式
  ```bash
  # macOS
  brew install fzf
  
  # Ubuntu/Debian
  apt install fzf
  ```

## 常见问题

### Q: 切换模型后不生效？
A: 需要重启 Claude Code 会话。关闭当前终端，重新打开并运行 `claude`。

### Q: 为什么不用 `deepseek-chat` 了？
A: DeepSeek 在 2026-04-24 发布了 V4 模型，旧模型将在 2026-07-24 弃用。建议迁移到 `deepseek-v4-pro` 或 `deepseek-v4-flash`。

### Q: AiXor 是什么？
A: AiXor 是一个统一代理服务，一个 API Key 可以访问多个底层模型（DeepSeek、Qwen、GLM 等），简化多模型管理。详见：https://docs.aixor.org/8336478m0

### Q: 如何查看当前使用的是哪个模型？
A: 运行 `./model-switch.sh status` 或查看 `~/.claude/settings.json`。

### Q: 如何恢复到原来的 Claude 官方模型？
A: 修改 `~/.claude/settings.json`，设置：
```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "your-claude-api-key",
    "ANTHROPIC_BASE_URL": "https://api.anthropic.com"
  }
}
```

## 脚本命令参考

| 命令 | 说明 |
|------|------|
| `list` / `ls` | 列出所有支持的提供商和模型 |
| `switch <provider> [model]` | 切换到指定提供商和模型 |
| `status` / `current` | 显示当前配置 |
| `backup` | 手动备份当前配置 |
| `restore <file>` | 从备份文件恢复配置 |
| `interactive` / `ui` | 交互式选择（需要 fzf） |
| `help` / `--help` / `-h` | 显示帮助信息 |

## 技术细节

- 脚本位置：项目根目录 `model-switch.sh`
- 配置位置：`~/.claude/settings.json`
- 备份位置：`~/.claude/backups/`
- 自动检测当前提供商（基于 Base URL）
- 根据模型类型自动设置合理的 `MAX_OUTPUT_TOKENS`
- 支持 Anthropic 和 OpenAI 两种兼容模式

## 许可证

本脚本属于项目模板的一部分，遵循项目许可证。
