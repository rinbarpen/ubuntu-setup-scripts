import { $ } from 'bun'
import { hasCommand, run } from '../../utils'
import { logStep, logInfo } from '../../utils/ui'

export const id = 'fisher'
export const label = 'Fisher (插件管理器)'
export const description = '安装 fisher + z, nvm, bass 插件'
export const category = 'system' as const
export const enabled = true
export const dependencies = ['shell']

export async function install(): Promise<void> {
  if (!(await hasCommand('fish'))) {
    logStep('fish shell 未安装，请先运行 shell 模块')
    return
  }

  if (!(await detect())) {
    logStep('安装 fisher...')
    await $`fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher"`.nothrow()
    logInfo('fisher 已安装')
  } else {
    logStep('fisher 已安装')
  }

  await $`fish -c "fisher install jethrokuan/z edc/bass nvm-community/fish-nvm"`.nothrow()
  logInfo('fisher: 完成')
}

export async function detect(): Promise<boolean> {
  if (!(await hasCommand('fish'))) return false
  const result = await run('fish -c "type fisher" 2>/dev/null')
  return result.exitCode === 0
}
