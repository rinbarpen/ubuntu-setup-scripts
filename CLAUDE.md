# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

```bash
bash scripts/setup.sh                        # Main entry: whiptail menu → run selected modules
bash scripts/modules/<name>.sh               # Run any single module standalone
bash scripts/tests/test-agent-configs.sh     # Integration test (no sudo required)
./model-switch.sh list                       # List supported AI providers
./model-switch.sh switch <provider> [model]  # Switch Claude Code provider/model
./model-switch.sh status                     # Show current Claude Code model config
./ssh-key-setup.sh                           # SSH key generation wizard
sudo bash create-user.sh                     # User creation wizard (SSH/FTP/SFTP)
```

## Architecture

### Entry Point & Infrastructure

- **`scripts/setup.sh`** — Main orchestrator. Sources `lib/utils.sh`, runs `sudo_check`, builds a whiptail checklist of 16 modules, executes selected modules in dependency-respecting order, prints pass/fail summary.
- **`scripts/lib/utils.sh`** — Shared library used by all modules. Provides `log_info`/`log_warn`/`log_err` (colored output), `need_cmd` (asserts command exists), `confirm` (y/N prompt), `sudo_check` (sudo with keep-alive loop).

### Modules (`scripts/modules/`)

16 independent setup scripts. Each defines `install_<name>()` and calls it at EOF. All source `utils.sh` for shared helpers.

| Category | Modules |
|----------|---------|
| System | `ubuntu-base` (packages, Docker, xrdp), `languages` (nvm/Node, Python, Rust, Go, uv), `shell` (fish + proxy), `fisher` |
| Tooling | `git` (config, SSH key, git-lfs), `zerotier` (VPN), `zellij`, `browsers`, `vms` |
| AI Agents | `openclaw`, `opencode`, `codex`, `claude-code`, `hermes-agent` |
| Ecosystem | `vibma` (Figma MCP bridge), `skills` (external skill collections) |

### Standalone Scripts

- **`model-switch.sh`** — Multi-provider model switcher for Claude Code (DeepSeek, Qwen, GLM, MiniMax, AiXor, OpenRouter, AIHubMix). Subcommands: `list`, `switch`, `status`, `backup`, `restore`.
- **Relay (中转站) support** — All three agent modules (claude-code, codex, opencode) support configuring relay/proxy endpoints for GPT/CLAUDE models (OpenRouter, AIHubMix, custom). See each module script for details.
- **`ssh-key-setup.sh`** — Interactive SSH key generation + remote copy + SSH config entry.
- **`create-user.sh`** — Interactive Linux user creation with SSH/FTP/SFTP and vsftpd config.

### Skills (`scripts/skills/`)

SKILL.md files shipped alongside modules, installed to `~/.claude/skills/`:
- `figma-vibma/SKILL.md` — Cross-platform Vibma/Figma connection bootstrap
- `figma-start-macos/SKILL.md` — macOS Figma session launcher

### Tests (`scripts/tests/`)

- **`test-agent-configs.sh`** — Integration test for the four agent config modules (claude-code, codex, opencode, hermes-agent). Creates a temp dir with stubs for `npm`/`whiptail`, runs each module twice (idempotency check), uses Python3 asserts to validate generated TOML/JSON/YAML configs. Run with `bash scripts/tests/test-agent-configs.sh` (no sudo needed).

## Module Conventions

- Every module defines `install_<name>()` and calls it as the last line.
- Modules are self-contained and can run independently (not just through `setup.sh`).
- Agent config modules follow this pattern: npm install → model selection prompt → config file generation (heredocs/Python3) → MCP server scenario selection → shell function setup.
- MCP server selection is scenario-based: frontend, backend, testing, analyst, stock, marketing, daily, chat.

## Config File Targets

| Tool | Config Path |
|------|-------------|
| Claude Code | `~/.claude/settings.json` |
| Codex | `~/.codex/config.toml` |
| opencode | `~/.config/opencode/opencode.json` |
| Claude Code profiles | `~/.config/cc-profiles/*.env` |
| Hermes Agent | `~/.hermes/config.yaml` |

## Design Spec

Full design document at `docs/superpowers/specs/2026-04-08-ubuntu-setup-scripts-design.md` covering architecture decisions, module implementation plans, error handling strategy, and testing approach.
