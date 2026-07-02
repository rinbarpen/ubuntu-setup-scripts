import { $ } from 'bun'
import { hasCommand, aptInstall, sudoRun } from '../utils'
import { logStep, logInfo, input } from '../utils/ui'

export const id = 'zerotier'
export const label = 'ZeroTier VPN'
export const description = '安装 ZeroTier VPN 并加入网络'
export const category = 'other' as const
export const enabled = false

export async function install(): Promise<void> {
  if (await hasCommand('zerotier-cli')) {
    logStep('ZeroTier 已安装')
  } else {
    logStep('安装 ZeroTier...')
    await sudoRun('curl -s https://install.zerotier.com | bash')
  }

  const networkId = await input({ message: 'ZeroTier 网络 ID（留空跳过）' })
  if (typeof networkId === 'string' && networkId.trim()) {
    await $`sudo zerotier-cli join ${networkId.trim()}`.nothrow()
    logInfo(`已加入 ZeroTier 网络: ${networkId.trim()}`)
  }

  logInfo('zerotier: 完成')
}

export async function detect(): Promise<boolean> {
  return hasCommand('zerotier-cli')
}
