import { $ } from 'bun'
import { hasCommand } from '../../utils'
import { logStep, logInfo } from '../../utils/ui'

export const id = 'paseo'
export const label = 'Paseo (Agent Orchestration)'
export const description = '安装 Paseo CLI + daemon 配置 + MCP'
export const category = 'agent' as const
export const enabled = true

export async function install(): Promise<void> {
  if (await hasCommand('paseo')) {
    logStep('Paseo 已安装')
    return
  }
  logStep('安装 Paseo...')
  await $`npm install -g paseo`.nothrow()
  logInfo('paseo: 完成')
}

export async function detect(): Promise<boolean> {
  return hasCommand('paseo')
}
