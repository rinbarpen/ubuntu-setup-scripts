# DeepSeek 配置说明

## 已完成的配置

`~/.claude/settings.json` 已更新为使用 DeepSeek 模型：

```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "sk-...",
    "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
    "ANTHROPIC_MODEL": "deepseek-chat",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-reasoner",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "deepseek-chat",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "deepseek-chat",
    "CLAUDE_CODE_SUBAGENT_MODEL": "deepseek-chat",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "8192"
  }
}
```

## 模型说明

| 模型 | 用途 | 特点 |
|------|------|------|
| `deepseek-chat` | 通用对话 | DeepSeek V3，性价比高 |
| `deepseek-reasoner` | 推理任务 | DeepSeek R1，擅长复杂推理 |
| `deepseek-coder` | 代码任务 | 专注编程场景 |

## 切换模型

使用提供的脚本快速切换：

```bash
# 切换到 deepseek-chat (默认)
./switch-to-deepseek.sh

# 切换到 deepseek-reasoner
./switch-to-deepseek.sh reasoner

# 切换到 deepseek-coder
./switch-to-deepseek.sh coder
```

## 手动修改

也可以直接编辑 `~/.claude/settings.json` 文件，修改模型名称后重启 Claude Code 即可生效。

## 注意事项

1. DeepSeek API 通过 Anthropic 兼容接口提供
2. 需要有效的 DeepSeek API Token (以 `sk-` 开头)
3. 修改配置后需要重启 Claude Code 会话
4. `CLAUDE_CODE_MAX_OUTPUT_TOKENS` 建议设置为 8192（DeepSeek 的推荐值）
