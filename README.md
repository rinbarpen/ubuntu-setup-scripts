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
| `opencode` | opencode CLI + relay provider config + defaults + MCP |
| `codex` | codex CLI + multi-provider + codex-auth + features/TUI config |
| `claude-code` | Claude Code + cc-switch + provider profiles + GPT/Claude models |
| `hermes-agent` | Hermes CLI + model config + MCP |
| `paseo` | Paseo CLI + daemon config + MCP |
| `vibma` | Vibma MCP + Figma plugin installer + Figma skills |
| `skills` | Install and register external skill collections |

## Agent Tool Defaults

The agent modules write current default config targets:

| Tool | Config file |
|------|-------------|
| Codex | `~/.codex/config.toml` |
| Claude Code | `~/.claude/settings.json` |
| opencode | `~/.config/opencode/opencode.json` |
| Hermes Agent | `~/.hermes/config.yaml` |
| Paseo | `~/.paseo/config.json` |

`codex` leaves any legacy `~/.codex/config.yaml` in place, but no longer writes it.

## Relay / Proxy (中转站) Model Support

All three agent tools (Claude Code, codex, opencode) support configuring relay/proxy endpoints to route GPT and Claude models through third-party services:

| Service | Endpoint | Description |
|---------|----------|-------------|
| **OpenRouter** | `https://openrouter.ai/api/v1` | Routes GPT, Claude, and other models |
| **AIHubMix** | `https://aihubmix.com/v1` | Multi-model relay endpoint |
| **Custom** | User-defined | Any relay/proxy endpoint |

### Quick Start: GPT/Claude via Relay

**Claude Code:**
1. Run `claude-code` setup, select a GPT or Claude model
2. Add an `openrouter` or `aihubmix` provider profile  
3. Use `cc-switch openrouter` to activate, or `./model-switch.sh switch openrouter openai/gpt-4o`

**Codex:**
1. Run `codex` setup, add `openrouter` or `aihubmix` as provider type
2. Enter API key, select the relay model as default

**opencode:**
1. Run `opencode` setup, select `openrouter/openai/gpt-4o` or similar
2. Configure relay when prompted (or accept pre-registered providers)

## Using DeepSeek Models

These scripts support DeepSeek V4 Pro and V4 Flash across all three agent tools:

### Prerequisites
DeepSeek's official API uses OpenAI format. To use DeepSeek with **Claude Code**, you need an **Anthropic API-compatible gateway** (e.g., OpenRouter, or self-hosted One-API).

### Claude Code + DeepSeek
1. Run `claude-code` setup
2. Add a `deepseek` provider profile
3. Select `deepseek-v4-pro` or `deepseek-v4-flash`

### Codex + DeepSeek
- The `deepseek` provider type has `base_url = "https://api.deepseek.com"` and `wire_api = "chat"`
- Select model during `codex` setup

### opencode + DeepSeek
- `deepseek/deepseek-v4-flash` is the default model
- Uses `@ai-sdk/deepseek` provider with `DEEPSEEK_API_KEY`

## Structure

```
scripts/
├── setup.sh          # Main entry: whiptail menu → run selected modules
├── lib/
│   ├── utils.sh      # Shared helpers (logging, sudo_check, confirm)
│   └── api.sh        # API key persistence (api_key_get / api_key_set)
├── modules/          # One script per module
├── tests/
│   └── test-agent-configs.sh  # Integration test for agent config modules
skills/               # SKILL.md files shipped alongside modules
model-switch.sh       # Standalone multi-provider model switcher (7 providers)
ssh-key-setup.sh      # SSH key generation wizard
create-user.sh        # Interactive user creation wizard
```

## Requirements

- Ubuntu 22.04 or 24.04
- `sudo` access
- `whiptail` (pre-installed on Ubuntu)

## License

MIT — see [LICENSE](LICENSE)
