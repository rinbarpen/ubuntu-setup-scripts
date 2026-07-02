import { hasCommand, aptInstall, sudoRun } from '../utils'
import { logStep, logInfo, confirm } from '../utils/ui'

export const id = 'vms'
export const label = 'VMs (VirtualBox + QEMU/KVM)'
export const description = '安装 VirtualBox, QEMU/KVM 虚拟化工具'
export const category = 'other' as const
export const enabled = false

export async function install(): Promise<void> {
  if (!(await hasCommand('virtualbox'))) {
    logStep('安装 VirtualBox...')
    await aptInstall('virtualbox virtualbox-ext-pack')
    logInfo('VirtualBox 已安装')
  } else {
    logStep('VirtualBox 已安装')
  }

  const doKvm = await confirm({ message: '安装 QEMU/KVM？', defaultValue: false })
  if (doKvm === true) {
    await aptInstall('qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager')
    const user = process.env.USER || process.env.LOGNAME || ''
    if (user) {
      await sudoRun(`usermod -aG libvirt ${user}`)
      await sudoRun(`usermod -aG kvm ${user}`)
      logInfo(`用户 ${user} 已加入 libvirt/kvm 组`)
    }
  }

  logInfo('vms: 完成')
}

export async function detect(): Promise<boolean> {
  return hasCommand('virtualbox') || hasCommand('qemu-kvm')
}
