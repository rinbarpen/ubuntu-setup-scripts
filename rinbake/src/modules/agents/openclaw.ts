import { $ } from 'bun'
import { hasCommand } from '../../utils'
import { logStep, logInfo } from '../../utils/ui'

export const id = 'openclaw'
export const label = 'OpenClaw'
export const description = '安装 openclaw 工具'
export const category = 'agent' as const
export const enabled = false

export async function install(): Promise<void> {
  if (await hasCommand('openclaw')) {
    logStep('openclaw 已安装')
    return
  }
  logStep('安装 openclaw...')
  await $`npm install -g openclaw`.nothrow()
  logInfo('openclaw: 完成')
}

export async function detect(): Promise<boolean> {
  return hasCommand('openclaw')
}
