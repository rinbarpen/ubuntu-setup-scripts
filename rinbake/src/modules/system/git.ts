import { $ } from 'bun'
import { hasCommand, aptInstall } from '../../utils'
import { logStep, logInfo, input, confirm } from '../../utils/ui'

export const id = 'git'
export const label = 'Git (配置 + SSH Key + git-lfs)'
export const description = 'git 用户配置、SSH key 生成、git-lfs 安装'
export const category = 'system' as const
export const enabled = true

export async function install(): Promise<void> {
  logStep('git-lfs...')
  if (!(await hasCommand('git-lfs'))) {
    await aptInstall('git-lfs')
    await $`git lfs install`.nothrow()
  }

  const name = await input({ message: 'Git 用户名', defaultValue: '' })
  if (typeof name === 'string' && name.trim()) {
    await $`git config --global user.name ${name.trim()}`.nothrow()
  }

  const email = await input({ message: 'Git 邮箱', defaultValue: '' })
  if (typeof email === 'string' && email.trim()) {
    await $`git config --global user.email ${email.trim()}`.nothrow()
  }

  const doSsh = await confirm({ message: '生成 SSH key (ed25519)？', defaultValue: true })
  if (doSsh === true) {
    const home = process.env.HOME || '/root'
    const keyPath = `${home}/.ssh/id_ed25519`
    if (await Bun.file(keyPath).exists()) {
      logStep('SSH key 已存在')
    } else {
      await $`mkdir -p ${home}/.ssh`.nothrow()
      const emailVal = typeof email === 'string' ? email.trim() : ''
      await $`ssh-keygen -t ed25519 -C ${emailVal || 'rinbake'} -f ${keyPath} -N ""`.nothrow()
      const pubKey = await Bun.file(`${keyPath}.pub`).text()
      logInfo(`SSH public key:\n${pubKey.trim()}`)
    }
  }

  logInfo('git: 完成')
}

export async function detect(): Promise<boolean> {
  return hasCommand('git-lfs')
}
