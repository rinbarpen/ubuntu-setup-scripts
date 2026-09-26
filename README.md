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
| `github-cli` | GitHub CLI (gh) 安装与认证 |
| `zerotier` | ZeroTier VPN |
| `zellij` | zellij terminal multiplexer |
| `browsers` | Chrome, Firefox |
| `vms` | VirtualBox, QEMU/KVM |
| `openclaw` | openclaw (npm) |
| `opencode` | opencode CLI + OmniRoute model gateway + defaults + MCP |
| `codex` | codex CLI + multi-provider + codex-auth + features/TUI config |
| `claude-code` | Claude Code + cc-switch + provider profiles + GPT/Claude models |
| `omniroute` | OmniRoute 本机 Gateway + Dashboard + Provider + Codex/Claude/OpenCode 配置 |
| `hermes-agent` | Hermes CLI + model config + MCP |
| `paseo` | Paseo CLI + daemon config + MCP |
| `orca` | Orca Linux AppImage + CLI + Agent hooks/skills + headless service |
| `skills` | Install and register external skill collections |

## Agent Tool Defaults

The agent modules write current default config targets:

| Tool | Config file |
|------|-------------|
| Codex | `~/.codex/config.toml` |
| Claude Code | `~/.claude/settings.json` |
| Claude Code MCP | `~/.claude.json` |
| opencode | `~/.config/opencode/opencode.json` |
| Hermes Agent | `~/.hermes/config.yaml` |
| Paseo | `~/.paseo/config.json` |
| Orca | `/opt/orca/orca-linux.AppImage`, `/etc/systemd/system/orca-serve.service` |

`codex` leaves any legacy `~/.codex/config.yaml` in place, but no longer writes it.

### Paseo / Orca

```bash
rinbake install paseo orca
rinbake configure paseo orca

# Paseo daemon
paseo daemon config get daemon.listen
paseo daemon start

# Orca hooks and service
orca-ide agent hooks status --json
sudo systemctl status orca-serve.service
```

The Paseo module preserves existing fields in `~/.paseo/config.json` and lets you
choose the daemon listen address, MCP, Agent injection, and relay settings. Orca
uses the Linux AppImage and registers the non-conflicting `orca-ide` command.
The headless service uses port `6768` by default; enter a reachable pairing
address when configuring remote clients. Orca's `--pairing-address` advertises
the client endpoint and does not change the listener bind address.

### Current machine profile

The current Codex and Claude Code setup is synchronized into
`profiles/current-machine/`, `.claude/settings.json`, and
`gpt-5.6-sol-unrestricted-v42.md`. Credential values are not stored in the
project; user-level credentials remain external.

## OmniRoute Model Gateway

OmniRoute is the model gateway for all model-routing flows. The Agent modules
and legacy shell installers use the local service instead of writing direct
third-party relay endpoints.

| Client | Endpoint | Default model |
|--------|----------|---------------|
| Codex | `http://localhost:20128/v1` | `auto` |
| Claude Code | `http://localhost:20128` | `auto` |
| OpenCode | `http://localhost:20128/v1` | `omniroute/auto` |
| Pi / OMP | `http://localhost:20128/v1` | `omniroute/auto` |

### Quick Start

```bash
rinbake install omniroute
rinbake omniroute status
rinbake omniroute configure codex
rinbake omniroute configure claude-code
rinbake omniroute configure opencode
rinbake omniroute providers
```

Provider connections and dynamic model catalogs are managed in Dashboard →
Providers. Browser or OAuth connections such as `chatgpt-web` and
`claude-web` stay in the Dashboard and never require copying cookies or tokens
into the terminal.

`rinbake install` or `rinbake configure` for Codex, Claude Code, or OpenCode
ensures the local gateway is installed and running before applying the official
OmniRoute client configuration. Pi and OMP write the compatible local endpoint
but do not start the service automatically; use `rinbake omniroute start` when
needed.

A migration backup is created under
`~/.config/rinbake/migrations/<timestamp>/` when legacy relay settings are first
converted. Unknown fields, MCP settings, and permissions are preserved.

## Using DeepSeek Models

The synchronized Claude Code baseline uses the `haiku` alias through OmniRoute.
Use `auto`, `auto/coding`, or a Dashboard model ID when routing to DeepSeek.

DeepSeek can also remain configured as a direct official API provider:

### Prerequisites
DeepSeek's official API uses OpenAI format. Claude Code should normally reach it through OmniRoute's Anthropic-compatible gateway.

### Claude Code + DeepSeek
1. Run `claude-code` setup
2. Add a `deepseek` provider profile
3. Select `deepseek-v4-pro` or `deepseek-v4-flash`

### Codex + DeepSeek
- The `rinbake` Codex module emits provider entries with the current `wire_api = "responses"` value
- Select model during `codex` setup

### opencode + DeepSeek
- `omniroute/auto` is the default model
- Uses the local OmniRoute `/v1` endpoint; direct DeepSeek remains available as an explicit provider

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

## ego-lite on macOS

The repository includes the synchronized `ego-browser` (ego-lite) skill. On a Mac, run:

```bash
sh scripts/install-ego-lite-macos.sh
```

Use `--skill-only` to install only the Codex skill. The full command also installs and launches ego lite; finish its first-run onboarding in the app.

## rinbake CLI

`rinbake/` 是独立的 bun CLI 工具，提供交互式 Dev环境配置向导。

```bash
cd rinbake
bash install.sh    # 全局安装后可直接使用 rinbake <command>
```

子命令：

| 命令 | 说明 |
|------|------|
| `rinbake init` | 交互式安装向导 |
| `rinbake install [module...]` | 安装模块 |
| `rinbake install --all` | 全部安装 |
| `rinbake configure [module...]` | 配置模块 |
| `rinbake update [codex|claude-code]` | 更新 CLI 并迁移当前配置 |
| `rinbake update omniroute` | 更新 OmniRoute 并保留本机状态/Provider 配置 |
| `rinbake install omniroute` | 安装并启动 OmniRoute Gateway |
| `rinbake omniroute <action>` | 管理 OmniRoute 服务、Provider 和客户端配置 |
| `rinbake keys` | API Key 管理 |
| `rinbake mcp` | MCP 服务器管理 |
| `rinbake status` | 查看安装状态 |

GitHub CLI 模块：

```bash
rinbake install github-cli
rinbake configure github-cli
```

`rinbake configure github-cli` 会调用 GitHub CLI 原生认证流程，认证信息由 `gh` 管理。

### Codex / Claude Code 更新

```bash
rinbake update codex claude-code
```

该命令先升级 CLI，再迁移已有设置：Codex 和 Claude Code 接入本机 OmniRoute，同时保留 reasoning、审批、TUI/Agent 设置、未知字段、已有权限规则和 MCP 配置。旧中转配置会先备份到 `~/.config/rinbake/migrations/`。

### OmniRoute Gateway

```bash
rinbake install omniroute
rinbake omniroute status
rinbake omniroute configure codex
rinbake omniroute configure claude-code
rinbake omniroute configure opencode
rinbake omniroute providers
```

OmniRoute 默认运行在 `http://localhost:20128`。Codex/OpenCode 使用
`/v1`，Claude Code 使用 Gateway 根地址。Provider 连接在 Dashboard 的
`Providers` 页面完成，`chatgpt-web` 等需要浏览器授权的连接由
`skills/omniroute/SKILL.md` 引导。

## Requirements

- Ubuntu 22.04 or 24.04
- `sudo` access
- `whiptail` (pre-installed on Ubuntu)

## License

MIT — see [LICENSE](LICENSE)
