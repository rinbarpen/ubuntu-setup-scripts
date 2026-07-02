import { $ } from 'bun'
import { hasCommand, sudoRun } from '../utils'
import { logStep, logInfo } from '../utils/ui'

export const id = 'browsers'
export const label = 'Browsers (Chrome + Firefox)'
export const description = '安装 Chrome 和 Firefox 浏览器'
export const category = 'other' as const
export const enabled = false

export async function install(): Promise<void> {
  if (!(await hasCommand('google-chrome'))) {
    logStep('安装 Chrome...')
    await $`curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -o /tmp/chrome.deb`.nothrow()
    await $`sudo dpkg -i /tmp/chrome.deb`.nothrow()
    await sudoRun('apt-get install -f -y')
    logInfo('Chrome 已安装')
  } else {
    logStep('Chrome 已安装')
  }

  if (!(await hasCommand('firefox'))) {
    logStep('安装 Firefox...')
    await sudoRun('apt-get install -y firefox')
    logInfo('Firefox 已安装')
  } else {
    logStep('Firefox 已安装')
  }

  logInfo('browsers: 完成')
}

export async function detect(): Promise<boolean> {
  return hasCommand('google-chrome') || hasCommand('firefox')
}
