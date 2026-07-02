import { aptInstall, sudoRun, hasPkg } from '../../utils'
import { logStep, logInfo, confirm } from '../../utils/ui'

export const id = 'ubuntu-base'
export const label = 'Ubuntu Base (系统工具 + Docker + xrdp)'
export const description = '安装系统基础组件、Docker、xrdp'
export const category = 'system' as const
export const enabled = true

export async function install(): Promise<void> {
  logStep('更新 apt 并安装基础包...')
  await sudoRun('apt-get update -qq')
  await aptInstall(
    'curl', 'wget', 'git', 'htop', 'tree', 'unzip', 'zip',
    'build-essential', 'software-properties-common', 'apt-transport-https',
    'ca-certificates', 'gnupg', 'lsb-release',
  )

  if (!(await hasPkg('docker-ce'))) {
    logStep('安装 Docker...')
    await sudoRun(`
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
      apt-get update -qq
      apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    `)
    const user = process.env.USER || process.env.LOGNAME || ''
    if (user) {
      await sudoRun(`usermod -aG docker ${user}`)
      logStep(`用户 ${user} 已加入 docker 组（重新登录后生效）`)
    }
  } else {
    logStep('Docker 已安装')
  }

  const doXrdp = await confirm({ message: '安装 xrdp（远程桌面）？', defaultValue: false })
  if (doXrdp === true) {
    await aptInstall('xrdp')
    await sudoRun('systemctl enable --now xrdp')
  }

  logInfo('ubuntu-base: 完成')
}

export async function detect(): Promise<boolean> {
  return hasPkg('build-essential')
}
