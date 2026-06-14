# Ubuntu Setup Scripts — Design Spec

**Date:** 2026-04-08
**Status:** Approved

---

## Context

After a fresh Ubuntu install, manually configuring the development environment is tedious and error-prone. This project provides a modular, menu-driven setup script collection so the user can quickly reproduce a consistent dev environment on any new machine. Modules can be run individually or via a whiptail checklist menu.

---

## Architecture

### Directory Structure

```
scripts/
├── setup.sh              # Main entry: whiptail checklist → run selected modules
├── lib/
│   └── utils.sh          # Shared helpers: log/info/warn/err, need_cmd, sudo_check, confirm
└── modules/
    ├── ubuntu-base.sh    # System tools, Docker, terminal enhancers
    ├── languages.sh      # nvm/Node.js, Python/pip, Rust, miniconda, uv, Go
    ├── git.sh            # user.name/email, SSH key (ed25519), aliases, proxy
    ├── shell.sh          # fish install + proxy_on/off/status functions
    ├── fisher.sh         # fisher + z, nvm, bass; nvm use latest
    ├── zerotier.sh       # ZeroTier install + optional network join
    ├── zellij.sh         # zellij terminal multiplexer install
    ├── browsers.sh       # Chrome, Firefox
    ├── vms.sh            # VirtualBox, QEMU/KVM
    ├── openclaw.sh       # npm install -g openclaw
    ├── opencode.sh       # opencode CLI + relay provider config + MCP
    ├── codex.sh          # codex CLI + multi-provider + codex-auth
    ├── claude-code.sh    # Claude Code + cc-switch + provider profiles
    ├── hermes-agent.sh   # Hermes CLI + model config + MCP
    └── paseo.sh          # Paseo CLI + daemon config + MCP
```

Total: 16 modules.

---

## Components

### `lib/utils.sh`

Shared functions sourced by all modules. Each module script begins with:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"
```

This allows both `setup.sh` and standalone `bash modules/git.sh` invocations to work correctly.

Functions:
- `log_info / log_warn / log_err` — colored output (green/yellow/red)
- `need_cmd <cmd>` — abort with clear message if command not found
- `sudo_check` — `sudo -v` upfront; background loop to keep alive
- `confirm <prompt>` — prompt y/n, return 0/1

---

### `setup.sh` — Main Entry

1. Source `lib/utils.sh`
2. `sudo_check` to acquire sudo early
3. Build `whiptail --checklist` listing all 11 modules. Capture output with redirect:
   ```bash
   CHOICES=$(whiptail --checklist "Select modules to install" 20 60 9 \
     "ubuntu-base" "System tools + Docker" ON \
     ... 3>&1 1>&2 2>&3)
   ```
4. Parse `$CHOICES`; for each selected module run `bash "$SCRIPT_DIR/modules/${module}.sh"` and capture exit code
5. After all modules complete, print per-module pass/fail summary:
   ```
   [OK]   ubuntu-base
   [FAIL] languages (exit 1)
   [OK]   git
   ```
   A failed module does NOT stop remaining modules — the loop uses `|| true` and records the exit code.

**Execution order** (important for dependencies):
`ubuntu-base → languages → shell → fisher → git → zerotier → zellij → openclaw → opencode → codex → claude-code → hermes-agent → paseo`

This order ensures:
- `languages` (nvm) runs before `fisher` (which invokes `nvm use latest`)
- `shell` (fish) runs before `fisher` (which requires fish)
- `ubuntu-base` (npm via nvm happens in `languages` instead, so `openclaw`/`codex`/`claude-code` come last)

Supports standalone module runs: `bash modules/git.sh`

---

### `modules/ubuntu-base.sh`

```
apt update && apt upgrade -y
apt install -y:
  build-essential curl wget git vim neovim tmux htop btop aria2
  fzf ripgrep bat eza
  zip unzip p7zip-full p7zip-rar tar gzip bzip2 xz-utils zstd
  net-tools iproute2 iputils-ping nmap traceroute dnsutils
Docker: official apt source → docker-ce, docker-ce-cli, containerd.io, docker-compose-plugin
Add user to docker group
nvtop: apt install nvtop (fall back to pip install nvtop if not available)
xrdp: apt install xrdp → systemctl enable --now xrdp → adduser xrdp ssl-cert → ufw allow 3389/tcp (if ufw active)
```

---

### `modules/languages.sh`

| Tool | Install method |
|------|---------------|
| Node.js (nvm) | `curl nvm install script` → `nvm install --lts` |
| Python3 / pip | `apt install python3 python3-pip python3-venv` |
| Rust (rustup) | `curl https://sh.rustup.rs -sSf \| sh -s -- -y` |
| miniconda | Download latest `Miniconda3-latest-Linux-x86_64.sh` → `bash ... -b -p ~/miniconda3` |
| uv | Preferred: `curl -LsSf https://astral.sh/uv/install.sh \| sh`. No pip fallback. |
| Go | Query `https://go.dev/VERSION?m=text` for latest version string → download tar → extract to `/usr/local/go` → add to PATH in `~/.bashrc` and `~/.config/fish/conf.d/go.fish` |

---

### `modules/git.sh`

0. `apt install git-lfs` → `git lfs install`
1. Prompt for `user.name` and `user.email`; if user presses Enter with empty input, skip that field with a warning (do not abort)
2. Generate `~/.ssh/id_ed25519` if not exists; display public key at end
3. Write common aliases to `~/.gitconfig`:
   - `st = status`, `co = checkout`, `br = branch`
   - `lg = log --oneline --graph --decorate --all`
4. Optional: `confirm "Configure git HTTP proxy?"` → prompt for address → `git config --global http.proxy`

---

### `modules/shell.sh`

1. `apt install fish`
2. `confirm "Set fish as default shell?"` → `chsh -s $(which fish)` if yes
3. Prompt for proxy address (default: `http://127.0.0.1:7890`); used in proxy functions
4. Write `~/.config/fish/functions/proxy_on.fish`:
   ```fish
   function proxy_on
     set -gx http_proxy $PROXY_ADDR
     set -gx https_proxy $PROXY_ADDR
     set -gx all_proxy $PROXY_ADDR
     echo "Proxy ON: $PROXY_ADDR"
   end
   ```
   Where `PROXY_ADDR` is substituted with the actual address at write time.
5. Write `proxy_off.fish` (unset all proxy vars) and `proxy_status.fish` (print current values)
6. Write equivalent functions to `~/.bashrc` as bash functions

---

### `modules/fisher.sh`

Requires fish. Guards: `need_cmd fish`.

nvm availability check: test for `~/.nvm/nvm.sh` existence, then source it before calling `nvm use latest`. If `~/.nvm/nvm.sh` does not exist, skip with `log_warn "nvm not found, skipping nvm use latest"`.

```fish
curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
fisher install jethrokuan/z
fisher install jorgebucaran/nvm
fisher install edc/bass
# Only if nvm available:
nvm use latest
```

All commands run via `fish -c "..."`.

---

### `modules/browsers.sh`

whiptail checklist within the module to select browsers:
- **Google Chrome**: download `.deb` from `dl.google.com` → `dpkg -i` → `apt install -f`
- **Firefox**: `apt install firefox` (or snap if apt version unavailable)

---

### `modules/vms.sh`

whiptail checklist to select:
- **VirtualBox**: add Oracle apt repo + key → `apt install virtualbox-7.0` → `adduser $USER vboxusers`
- **QEMU/KVM**: `apt install qemu-kvm libvirt-daemon-system virt-manager bridge-utils` → `adduser $USER libvirt kvm` → `systemctl enable --now libvirtd`

---

### `modules/zerotier.sh`

1. Install: `curl -s https://install.zerotier.com | sudo bash`
   - Note: remote pipe to bash is the official ZeroTier install method. No additional integrity check is performed beyond HTTPS.
2. `systemctl enable --now zerotier-one`
3. `confirm "Join a ZeroTier network?"` → prompt for network ID → `sudo zerotier-cli join <id>`

---

### `modules/zellij.sh`

1. If `cargo` is available: `cargo install zellij`
2. Else: query GitHub API `https://api.github.com/repos/zellij-org/zellij/releases/latest` for latest version → download `zellij-x86_64-unknown-linux-musl.tar.gz` → extract binary to `/usr/local/bin/zellij`
3. Write default config `~/.config/zellij/config.kdl` only if it does not exist

---

### `modules/openclaw.sh`

1. `need_cmd npm`
2. `npm install -g openclaw`

---

### `modules/codex.sh`

**Prerequisites:** `need_cmd npm`, `need_cmd python3`

**Step 1 — Install codex CLI:**
```bash
npm install -g @openai/codex
```

**Step 2 — Model Provider Profiles (up to 5):**
- whiptail menu to add model providers. Built-in types:
  - `openai` — `https://api.openai.com/v1`, Responses API, `OPENAI_API_KEY`
  - `deepseek` — `https://api.deepseek.com`, Chat API, `DEEPSEEK_API_KEY`
  - `openrouter` — `https://openrouter.ai/api/v1`, Chat API, `OPENROUTER_API_KEY` (GPT/CLAUDE via relay)
  - `aihubmix` — `https://aihubmix.com/v1`, Chat API, `AIHUBMIX_API_KEY` (GPT/CLAUDE via relay)
  - `azure` — user-provided endpoint, Responses API, `AZURE_OPENAI_API_KEY`
  - `ollama` — `http://localhost:11434/v1`, Chat API, no key (local)
  - `lmstudio` — `http://localhost:1234/v1`, Chat API, no key (local)
  - `custom` — fully configurable: any base URL, env key name, and API format (chat/responses)
- API keys stored in `~/.config/rinbarpen/api-keys.env` via shared `lib/api.sh`
- Multiple providers coexist in `[model_providers.<id>]` table in `config.toml`

**Step 3 — Default provider & model selection:**
- Select default provider from configured list via whiptail menu
- Enter model ID (e.g. `gpt-5`, `deepseek-v4-pro`)
- Stored as `model_provider` and `model` in `config.toml`

**Step 4 — Plan mode model:**
- whiptail menu with options: `deepseek-v4-pro`, `deepseek-v4-flash`, `gpt-5.5`, `gpt-4o`, `claude-sonnet-4-20250514`, `custom`, `do-not-set`

**Step 5 — Write defaults to `~/.codex/config.toml`:**
```toml
model_reasoning_effort = "medium"
plan_mode_reasoning_effort = "xhigh"
approval_policy = "on-request"
sandbox_mode = "workspace-write"
plan_model = "deepseek-v4-pro"  # selected plan model

[features]
memories = false
hooks = true
undo = false
apps = false
network_proxy = false

[tui]
animations = true
alternate_screen = "never"
show_tooltips = false

[model_providers.openai]
name = "OpenAI"
base_url = "https://api.openai.com/v1"
env_key = "OPENAI_API_KEY"
wire_api = "responses"
```

**Step 6 — `codex-auth` function:**
Written to `~/.config/fish/functions/codex_auth.fish` and `~/.bashrc`:
- Detects the default `model_provider` from `~/.codex/config.toml`
- Prompts for the correct API key env var: `OPENAI_API_KEY`, `DEEPSEEK_API_KEY`, `OPENROUTER_API_KEY`, or `AIHUBMIX_API_KEY`
- Exports the key in current shell session (session-only)

**Step 7 — MCP Toolkits:**
Same scenario-based selection as other modules, writes to `~/.codex/config.toml` under `[mcp_servers]`.

**Deprecated keys:** `openai_base_url` and `openai_api_key` are removed from config (migrated to `model_providers`).

---

### `modules/claude-code.sh`

**Prerequisites:** `need_cmd npm`

**Step 1 — Install Claude Code CLI:**
```bash
npm install -g @anthropic-ai/claude-code
```

**Step 2 — Model selection (multi-provider):**
- whiptail menu with options: `deepseek-v4-pro`, `deepseek-v4-flash`, `openai/gpt-4o`, `openai/gpt-4o-mini`, `openai/gpt-5.5`, `anthropic/claude-sonnet-4-20250514`, `anthropic/claude-opus-4-20250514`, `claude-sonnet-4-20250514` (direct), `custom`
- Default: `deepseek-v4-pro`
- Writes to `~/.claude/settings.json`: `"model": "deepseek-v4-pro"`

**Subordinate model defaults (context-aware):**
- DeepSeek models → `deepseek-v4-flash` for sonnet/haiku roles
- Claude models → same model for sonnet, `deepseek-v4-flash` for haiku
- GPT models → same model for sonnet, `deepseek-v4-flash` for haiku

**Step 3 — Provider profiles:**
For each provider, create `~/.config/cc-profiles/<name>.env`:

| Provider | Variables written |
|----------|------------------|
| anthropic | `ANTHROPIC_API_KEY` |
| openrouter | `ANTHROPIC_API_KEY`, `ANTHROPIC_BASE_URL=https://openrouter.ai/api/v1` |
| deepseek | `ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic`, `ANTHROPIC_API_KEY` |
| aihubmix | `ANTHROPIC_API_KEY`, `ANTHROPIC_BASE_URL=https://aihubmix.com/v1` |
| custom | `ANTHROPIC_API_KEY`, `ANTHROPIC_BASE_URL` (user provides both) |

**Step 4 — `cc-switch` function:**
Written to `~/.config/fish/functions/cc_switch.fish` and `~/.bashrc`:
- Usage: `cc-switch <profile>` (e.g. `cc-switch openrouter`)
- Loads `~/.config/cc-profiles/<profile>.env` by sourcing it
- Prints confirmation or lists available profiles if not found

**Step 5 — MCP Toolkits:**
Same scenario-based selection, writes to `~/.claude/settings.json` under `mcpServers`.

---

### `modules/opencode.sh`

**Prerequisites:** `need_cmd npm`, `need_cmd python3`

**Step 1 — Install opencode CLI:**
```bash
npm install -g opencode-ai
```

**Step 2 — Model selection:**
- whiptail menu with options (provider/model format):
  - DeepSeek: `deepseek/deepseek-v4-flash`, `deepseek/deepseek-v4-pro`, `deepseek/deepseek-chat`
  - OpenAI: `openai/gpt-5.5`, `openai/gpt-4o`, `openai/gpt-4o-mini`
  - Via OpenRouter: `openrouter/anthropic/claude-sonnet-4-20250514`, `openrouter/anthropic/claude-opus-4-20250514`, `openrouter/openai/gpt-5.5`, `openrouter/openai/gpt-4o`
  - Via AIHubMix: `aihubmix/openai/gpt-5.5`, `aihubmix/anthropic/claude-sonnet-4-20250514`
  - Custom: free-text `provider/model` string

**Step 3 — Relay configuration (OpenAI provider):**
- Optional whiptail menu: `none` (direct OpenAI), `openrouter`, `aihubmix`, `custom`
- Sets `baseURL` on the `@ai-sdk/openai` provider entry when relay is selected
- Pre-registers `openrouter` and `aihubmix` provider entries for use with model prefix routing
- Custom relay prompts for base URL and API key env var name

**Step 4 — Plan model selection:**
- whiptail menu: `openai/gpt-5.5`, `openai/gpt-4o`, `openrouter/openai/gpt-5.5`, `openrouter/anthropic/claude-sonnet-4-20250514`, `deepseek/deepseek-reasoner`, `custom`

**Step 5 — Write defaults to `~/.config/opencode/opencode.json`:**
```json
{
  "model": "deepseek/deepseek-v4-flash",
  "provider": {
    "deepseek": {
      "npm": "@ai-sdk/deepseek",
      "options": { "apiKey": "{env:DEEPSEEK_API_KEY}" }
    },
    "openai": {
      "npm": "@ai-sdk/openai",
      "options": { "apiKey": "{env:OPENAI_API_KEY}" }
    },
    "openrouter": {
      "npm": "@ai-sdk/openai",
      "options": {
        "apiKey": "{env:OPENROUTER_API_KEY}",
        "baseURL": "https://openrouter.ai/api/v1"
      }
    },
    "aihubmix": {
      "npm": "@ai-sdk/openai",
      "options": {
        "apiKey": "{env:AIHUBMIX_API_KEY}",
        "baseURL": "https://aihubmix.com/v1"
      }
    }
  },
  "agent": {
    "plan": {
      "model": "openai/gpt-5.5",
      "options": { "reasoningEffort": "xhigh" }
    }
  },
  "permission": {
    "edit": "ask",
    "bash": "ask",
    "external_directory": "ask"
  }
}
```

**Step 6 — MCP Toolkits:**
Same scenario-based selection, writes to `~/.config/opencode/opencode.json` under `mcp`.

```
setup.sh
  ├── source lib/utils.sh
  ├── sudo_check
  ├── whiptail checklist → CHOICES (via fd redirect)
  └── for each module in ORDERED_LIST:
        if module in CHOICES:
          bash modules/<name>.sh   # subprocess, sources utils.sh itself
          record exit code
  └── print summary table
```

Each module script:
```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"
# ... module logic
```

---

## Error Handling

- Each module runs with `set -euo pipefail`
- `need_cmd` aborts the module (not the main script) if a dependency is missing
- Optional/interactive steps use `|| true` with a logged warning
- User prompts that receive empty input skip the step with `log_warn` (do not abort)
- Main script captures module exit codes with `|| exit_codes[$module]=$?`; continues regardless
- Summary table printed at end shows per-module pass/fail

---

## Testing / Verification

1. Fresh Ubuntu 22.04/24.04 VM (requires TTY — Docker containers need `docker run -it`)
2. Run `bash setup.sh` → verify whiptail checklist appears with 16 modules
3. Select all modules → verify each completes and summary shows all OK
4. Per-module spot checks:
   - `git config --global user.name` — non-empty
   - `ssh -T git@github.com` — key accepted
   - `fish --version`, `fisher list` — installed plugins listed
   - `zerotier-cli status` — online
   - `zellij --version`
   - `codex --version`, `claude --version`, `opencode --version`
5. Test proxy functions in fish: `proxy_on`, `proxy_status` (shows address), `proxy_off` (vars unset)
6. Test `cc-switch openrouter`: verify `echo $ANTHROPIC_BASE_URL` shows openrouter URL in same session
7. Test `cc-switch aihubmix`: verify `echo $ANTHROPIC_BASE_URL` shows aihubmix URL
8. Test `codex-auth`: run function, enter key, verify appropriate env var reflects input (detects provider from config)
9. Test opencode relay: verify `~/.config/opencode/opencode.json` contains `openrouter` and `aihubmix` provider entries with `baseURL` fields
10. Test codex model config: verify `~/.codex/config.toml` contains `[model_providers]` table when providers configured
11. Test `zellij` fallback: on a system without cargo, run module and verify binary at `/usr/local/bin/zellij`
12. Test `nvm use latest` via fish after `fisher.sh` (confirm node --version updates)
13. Test standalone module: `bash scripts/modules/git.sh` without running `setup.sh` first
14. Test `model-switch.sh list` shows all 7 providers including openrouter and aihubmix
