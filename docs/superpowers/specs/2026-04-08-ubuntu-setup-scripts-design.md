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
    └── codex-cc.sh       # codex CLI + Claude Code + full-auto + cc-switch + codex-auth
```

Total: 11 modules.

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
`ubuntu-base → languages → shell → fisher → git → zerotier → zellij → openclaw → codex-cc`

This order ensures:
- `languages` (nvm) runs before `fisher` (which invokes `nvm use latest`)
- `shell` (fish) runs before `fisher` (which requires fish)
- `ubuntu-base` (npm via nvm happens in `languages` instead, so `openclaw`/`codex-cc` come last)

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

### `modules/codex-cc.sh`

**Prerequisites:** `need_cmd npm`

**Step 1 — Install CLIs:**
```bash
npm install -g @openai/codex
npm install -g @anthropic-ai/claude-code
```

**Step 2 — Full-auto permissions for Claude Code:**

If `~/.claude/settings.json` exists, merge permissions; otherwise create new file.
User is warned before writing:
> "This will grant Claude Code full Bash/file access. Proceed? [y/N]"

```json
{
  "permissions": {
    "allow": ["Bash(*)", "Read(*)", "Write(*)", "Edit(*)", "Glob(*)", "Grep(*)"],
    "deny": []
  }
}
```

**Step 3 — Provider profiles:**

For each provider the user wants to configure, create `~/.config/cc-profiles/<name>.env`:

```bash
# ~/.config/cc-profiles/openrouter.env
export OPENAI_API_KEY="sk-or-..."
export OPENAI_BASE_URL="https://openrouter.ai/api/v1"
export ANTHROPIC_API_KEY=""
```

Supported variable names per provider:
| Provider | Variables written |
|----------|------------------|
| anthropic | `ANTHROPIC_API_KEY` |
| openai | `OPENAI_API_KEY` |
| openrouter | `OPENAI_API_KEY`, `OPENAI_BASE_URL` |
| custom | `OPENAI_API_KEY`, `OPENAI_BASE_URL` (user provides both) |

At install time, prompt: "Add a provider profile? [y/N]" → loop until user says no.

**Step 4 — `codex-auth` function:**

Written to `~/.config/fish/functions/codex_auth.fish` and `~/.bashrc`:
- Prompts the user to enter their OpenAI API key
- Exports `OPENAI_API_KEY` in the current shell session
- Does NOT write to file (session-only; for persistent keys use `cc-switch`)

**Step 5 — `cc-switch` function:**

Written to `~/.config/fish/functions/cc_switch.fish` and `~/.bashrc`:
- Usage: `cc-switch <profile>` (e.g. `cc-switch openrouter`)
- Loads `~/.config/cc-profiles/<profile>.env` by sourcing it in the current shell
- Prints confirmation: `Switched to profile: openrouter`
- If profile not found, lists available profiles

Profile files use `export KEY=VALUE` format (bash-compatible, sourced in both fish via `bass` and bash directly).

---

## Data Flow

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
2. Run `bash setup.sh` → verify whiptail checklist appears with 9 modules
3. Select all modules → verify each completes and summary shows all OK
4. Per-module spot checks:
   - `git config --global user.name` — non-empty
   - `ssh -T git@github.com` — key accepted
   - `fish --version`, `fisher list` — installed plugins listed
   - `zerotier-cli status` — online
   - `zellij --version`
   - `codex --version`, `claude --version`
5. Test proxy functions in fish: `proxy_on`, `proxy_status` (shows address), `proxy_off` (vars unset)
6. Test `cc-switch openrouter`: verify `echo $OPENAI_BASE_URL` shows openrouter URL in same session
7. Test `codex-auth`: run function, enter key, verify `echo $OPENAI_API_KEY` reflects input
8. Test `zellij` fallback: on a system without cargo, run module and verify binary at `/usr/local/bin/zellij`
9. Test `nvm use latest` via fish after `fisher.sh` (confirm node --version updates)
10. Test standalone module: `bash scripts/modules/git.sh` without running `setup.sh` first
