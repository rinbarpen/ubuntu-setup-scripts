# Ubuntu Setup Scripts

Modular, menu-driven setup scripts for quickly reproducing a consistent development environment on a fresh Ubuntu install.

## Usage

```bash
bash scripts/setup.sh
```

A whiptail checklist lets you pick which modules to install. Each module can also be run standalone:

```bash
bash scripts/modules/git.sh
```

## Modules

| Module | Description |
|--------|-------------|
| `ubuntu-base` | System tools, Docker, xrdp |
| `languages` | nvm/Node.js, Python, Rust, Go, uv |
| `shell` | fish shell + proxy functions |
| `fisher` | fisher + z, nvm, bass plugins |
| `git` | git config, SSH key (ed25519), git-lfs |
| `zerotier` | ZeroTier VPN |
| `zellij` | zellij terminal multiplexer |
| `browsers` | Chrome, Firefox |
| `vms` | VirtualBox, QEMU/KVM |
| `openclaw` | openclaw (npm) |
| `opencode` | opencode CLI + defaults + MCP |
| `codex-cc` | codex CLI + Claude Code + cc-switch + codex-auth |
| `vibma` | Vibma MCP + Figma plugin installer + Figma skills |
| `skills` | Install and register external skill collections |

## Agent Tool Defaults

The agent modules write current default config targets:

| Tool | Config file |
|------|-------------|
| Codex | `~/.codex/config.toml` |
| Claude Code | `~/.claude/settings.json` |
| opencode | `~/.config/opencode/opencode.json` |

`codex-cc` leaves any legacy `~/.codex/config.yaml` in place, but no longer writes it.

## Using DeepSeek Models

These scripts support DeepSeek V4 Pro and V4 Flash across all three agent tools:

### Prerequisites
DeepSeek's official API uses OpenAI format. To use DeepSeek with **Claude Code**, you need an **Anthropic API-compatible gateway** (e.g., OpenRouter, or self-hosted One-API).

### Claude Code + DeepSeek
1. Run `codex-cc` setup
2. Add a `deepseek` provider profile (enter your gateway URL and API key)
3. Select `deepseek-v4-pro` or `deepseek-v4-flash` as the default model in the interactive menu

### Codex + DeepSeek
- Codex CLI will use the model configured in `~/.codex/config.toml`
- Select your preferred model during `codex-cc` setup

### opencode + DeepSeek
- `deepseek/deepseek-v4-flash` is the default model
- `deepseek/deepseek-v4-pro` is available in the model selection menu
- Both use the `@ai-sdk/deepseek` provider with `DEEPSEEK_API_KEY`

## Structure

```
scripts/
├── setup.sh          # Main entry: whiptail menu → run selected modules
├── lib/
│   └── utils.sh      # Shared helpers (logging, sudo_check, confirm)
└── modules/          # One script per module
```

## Requirements

- Ubuntu 22.04 or 24.04
- `sudo` access
- `whiptail` (pre-installed on Ubuntu)

## License

MIT — see [LICENSE](LICENSE)
