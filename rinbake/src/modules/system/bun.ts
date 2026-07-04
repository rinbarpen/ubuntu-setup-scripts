import { $ } from 'bun'
import { hasCommand, appendToBashrcIfMissing } from '../../utils'
import { logStep, logInfo } from '../../utils/ui'

export const id = 'bun'
export const label = 'Bun (runtime + package manager)'
export const description = '安装 Bun JavaScript 运行时与包管理器'
export const category = 'system' as const
export const enabled = true

export async function install(): Promise<void> {
  const home = process.env.HOME || '/root'

  if (!(await hasCommand('bun'))) {
    logStep('安装 Bun...')
    await $`curl -fsSL https://bun.sh/install | bash`.nothrow()
    logInfo('Bun 已安装')
  } else {
    logStep('Bun 已安装')
  }

  // bashrc
  await appendToBashrcIfMissing('bun-path', 'export PATH="$HOME/.bun/bin:$PATH"')

  // fish
  const fishDir = `${home}/.config/fish/conf.d`
  await $`mkdir -p ${fishDir}`.nothrow()
  const fishBun = `${fishDir}/bun.fish`
  if (!(await Bun.file(fishBun).exists())) {
    await Bun.write(fishBun, 'set -gx PATH $HOME/.bun/bin $PATH\n')
  }

  logInfo('bun: 完成（重启 shell 或 source ~/.bashrc）')
}

export async function detect(): Promise<boolean> {
  return hasCommand('bun')
}
