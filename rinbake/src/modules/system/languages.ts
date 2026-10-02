import { $ } from 'bun'
import { aptInstall, hasCommand, runAsUser, targetHome, writeAsUser } from '../../utils'
import { logStep, logInfo, logWarn } from '../../utils/ui'

export const id = 'languages'
export const label = 'Languages (nvm/Node + Python + Rust + Go + uv)'
export const description = '安装 nvm/Node.js, Python, Rust, Go, uv'
export const category = 'system' as const
export const scope = 'mixed' as const
export const enabled = true

/** Fish bridge for the official Bash-based nvm install. */
export function nvmFishConfig(): string {
  return `# Managed by rinbake: expose the official ~/.nvm installation in Fish.
if type -q bass; and test -s "$HOME/.nvm/nvm.sh"
    function nvm
        bass source "$HOME/.nvm/nvm.sh" --no-use ';' nvm $argv
    end

    function nvm_find_nvmrc
        bass source "$HOME/.nvm/nvm.sh" --no-use ';' nvm_find_nvmrc
    end

    function load_nvm --on-variable PWD
        set -l node_alias default
        set -l target_node_version (nvm version default)
        if test "$target_node_version" = N/A
            # node is nvm's latest-version alias; use it when no default alias exists.
            set node_alias node
            set target_node_version (nvm version node)
        end
        set -l node_version (nvm version)
        set -l nvmrc_path (nvm_find_nvmrc)
        if test -n "$nvmrc_path"
            set -l nvmrc_node_version (nvm version (cat "$nvmrc_path"))
            if test "$nvmrc_node_version" = N/A
                nvm install (cat "$nvmrc_path")
                and nvm use (cat "$nvmrc_path")
            else if test "$nvmrc_node_version" != "$node_version"
                nvm use "$nvmrc_node_version"
            end
        else if test "$target_node_version" != N/A; and test "$node_version" != "$target_node_version"
            nvm use "$node_alias"
        end
    end

    load_nvm >/dev/stderr
end
`
}

export async function configureFishNvm(home: string): Promise<void> {
  if (!(await hasCommand('fish'))) return

  // The official nvm release is Bash-based. bass imports its functions and
  // environment into Fish, so install that bridge even when Fisher was not a
  // separately selected module.
  let fisher = await runAsUser`fish -c "type -q fisher"`
  if (fisher.exitCode !== 0) {
    fisher = await runAsUser`fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source; and fisher install jorgebucaran/fisher"`
  }
  if (fisher.exitCode !== 0) {
    logWarn('Fish nvm 配置跳过：Fisher 安装失败')
    return
  }

  const hasBass = await runAsUser`fish -c "type -q bass"`
  if (hasBass.exitCode !== 0) {
    const bass = await runAsUser`fish -c "fisher install edc/bass"`
    if (bass.exitCode !== 0) {
      logWarn(`Fish nvm 配置跳过：bass 安装失败 ${bass.stderr}`)
      return
    }
  }

  const fishConf = `${home}/.config/fish/conf.d/rinbake-nvm.fish`
  if (!(await writeAsUser(fishConf, nvmFishConfig()))) {
    logWarn(`Fish nvm 配置写入失败：${fishConf}`)
    return
  }
  logInfo('Fish nvm 配置已写入（新 Fish 会话可用 nvm）')
}

export async function install(): Promise<void> {
  const home = targetHome()

  // nvm + Node
  if (!(await Bun.file(`${home}/.nvm/nvm.sh`).exists())) {
    logStep('安装 nvm...')
    // Runs as the user: NVM_DIR defaults to $HOME, which under sudo is /root.
    await runAsUser`curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash`
    await runAsUser`export NVM_DIR=${home}/.nvm && [ -s ${home}/.nvm/nvm.sh ] && . ${home}/.nvm/nvm.sh && nvm install --lts && nvm alias default 'lts/*'`
    logInfo('Node.js 已安装')
  } else {
    logStep('nvm 已安装')
  }

  await configureFishNvm(home)

  // Python
  logStep('安装 Python 3...')
  await aptInstall('python3', 'python3-pip', 'python3-venv')

  // Rust
  if (!(await hasCommand('rustup'))) {
    logStep('安装 Rust...')
    await runAsUser`curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y`
    logInfo('Rust 已安装')
  } else {
    logStep('Rust 已安装')
  }

  // uv
  if (!(await hasCommand('uv'))) {
    logStep('安装 uv...')
    await runAsUser`curl -LsSf https://astral.sh/uv/install.sh | sh`
    logInfo('uv 已安装')
  } else {
    logStep('uv 已安装')
  }

  // Go
  if (!(await hasCommand('go'))) {
    logStep('安装 Go...')
    const version = (await $`curl -fsSL https://go.dev/VERSION?m=text`.text()).trim()
    const tarball = `${version}.linux-amd64.tar.gz`
    await $`curl -fsSL https://go.dev/dl/${tarball} -o /tmp/${tarball}`.nothrow()
    await $`sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf /tmp/${tarball}`.nothrow()
    await $`rm /tmp/${tarball}`.nothrow()

    const bashrc = `${home}/.bashrc`
    const text = await Bun.file(bashrc).exists() ? await Bun.file(bashrc).text() : ''
    const marker = '# rinbake: go path'
    if (!text.includes(marker)) {
      await writeAsUser(bashrc, text + `\n${marker}\nexport PATH=$PATH:/usr/local/go/bin:$HOME/go/bin\n`)
    }

    const fishDir = `${home}/.config/fish/conf.d`
    const fishGo = `${fishDir}/go.fish`
    if (!(await Bun.file(fishGo).exists())) {
      await writeAsUser(fishGo, 'set -gx PATH $PATH /usr/local/go/bin $HOME/go/bin\n')
    }

    logInfo(`Go ${version} 已安装`)
  } else {
    logStep('Go 已安装')
  }

  logInfo('languages: 完成（重启 shell；Bash 可 source ~/.bashrc，Fish 新会话可用 nvm）')
}

export async function detect(): Promise<boolean> {
  return hasCommand('node') && hasCommand('python3') && hasCommand('go')
}
