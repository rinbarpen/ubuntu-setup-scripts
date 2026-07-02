import { $ } from 'bun'
import { hasCommand, aptInstall } from '../utils'
import { logStep, logInfo } from '../utils/ui'

export const id = 'zellij'
export const label = 'Zellij (终端复用器)'
export const description = '安装 zellij terminal multiplexer'
export const category = 'other' as const
export const enabled = true

export async function install(): Promise<void> {
  if (await hasCommand('zellij')) {
    logStep('zellij 已安装')
    return
  }
  logStep('安装 zellij...')
  await aptInstall('zellij')
  logInfo('zellij: 完成')
}

export async function detect(): Promise<boolean> {
  return hasCommand('zellij')
}
