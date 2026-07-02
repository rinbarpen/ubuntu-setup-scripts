import { $ } from 'bun'
import { hasCommand, aptInstall, run } from '../../utils'
import { logStep, logInfo } from '../../utils/ui'

export const id = 'languages'
export const label = 'Languages (nvm/Node + Python + Rust + Go + uv)'
export const description = '安装 nvm/Node.js, Python, Rust, Go, uv'
export const category = 'system' as const
export const enabled = true

export async function install(): Promise<void> {
  const home = process.env.HOME || '/root'

  // nvm + Node
  if (!(await hasCommand('nvm'))) {
    logStep('安装 nvm...')
    await $`curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash`.nothrow()
    // Source nvm for this session
    await $`export NVM_DIR="${home}/.nvm" && [ -s "${home}/.nvm/nvm.sh" ] && . "${home}/.nvm/nvm.sh" && nvm install --lts && nvm use --lts`.nothrow()
    logInfo('Node.js 已安装')
  } else {
    logStep('nvm 已安装')
  }

  // Python
  logStep('安装 Python 3...')
  await aptInstall('python3', 'python3-pip', 'python3-venv')

  // Rust
  if (!(await hasCommand('rustup'))) {
    logStep('安装 Rust...')
    await run('curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y')
    logInfo('Rust 已安装')
  } else {
    logStep('Rust 已安装')
  }

  // uv
  if (!(await hasCommand('uv'))) {
    logStep('安装 uv...')
    await run('curl -LsSf https://astral.sh/uv/install.sh | sh')
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
      await Bun.write(bashrc, text + `\n${marker}\nexport PATH=$PATH:/usr/local/go/bin:$HOME/go/bin\n`)
    }

    const fishDir = `${home}/.config/fish/conf.d`
    await $`mkdir -p ${fishDir}`.nothrow()
    const fishGo = `${fishDir}/go.fish`
    if (!(await Bun.file(fishGo).exists())) {
      await Bun.write(fishGo, 'set -gx PATH $PATH /usr/local/go/bin $HOME/go/bin\n')
    }

    logInfo(`Go ${version} 已安装`)
  } else {
    logStep('Go 已安装')
  }

  logInfo('languages: 完成（重启 shell 或 source ~/.bashrc）')
}

export async function detect(): Promise<boolean> {
  return hasCommand('node') && hasCommand('python3') && hasCommand('go')
}
