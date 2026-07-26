import { $ } from 'bun'
import * as fs from 'node:fs'
import { hasCommand, sudoRun } from '../utils'
import { logStep, logInfo, logWarn, multiselect, input, confirm } from '../utils/ui'

export const id = 'docker-config'
export const label = 'Docker Registry Mirrors'
export const description = '配置 Docker 镜像加速器 (daemon.json)'
export const category = 'system' as const
export const enabled = true

const DAEMON_JSON = '/etc/docker/daemon.json'

export async function install(): Promise<void> {
  const dockerRunning = await $`sudo systemctl is-active --quiet docker`.nothrow()
  if (dockerRunning.exitCode !== 0) {
    logWarn('Docker 未运行')
    const start = await confirm({ message: '启动 Docker？', defaultValue: false })
    if (start !== true) {
      logInfo('docker-config: 跳过')
      return
    }
    await $`sudo systemctl start docker`.nothrow()
  }

  try {
    const content = fs.readFileSync(DAEMON_JSON, 'utf-8')
    const cfg = JSON.parse(content)
    const mirrors = cfg['registry-mirrors']
    if (Array.isArray(mirrors) && mirrors.length > 0) {
      logStep('当前镜像配置:')
      for (const m of mirrors) console.log(`  - ${m}`)
    }
  } catch {}

  const proceed = await confirm({ message: '配置 Docker 镜像加速器？', defaultValue: true })
  if (proceed !== true) {
    logInfo('docker-config: 跳过')
    return
  }

  const choices = await multiselect({
    message: '选择镜像源 (Space 切换)',
    options: [
      { value: 'dockerproxy', label: 'dockerproxy', hint: 'https://dockerproxy.cn', checked: true },
      { value: 'one-ms', label: 'one-ms', hint: 'https://docker.1ms.run', checked: true },
      { value: 'xuanyuan', label: 'xuanyuan', hint: 'https://docker.xuanyuan.me', checked: true },
      { value: 'netease', label: 'netease', hint: 'https://hub-mirror.c.163.com' },
      { value: 'baidu', label: 'baidu', hint: 'https://mirror.baidubce.com' },
      { value: 'tencent', label: 'tencent', hint: 'https://ccr.ccs.tencentyun.com' },
      { value: 'aliyun', label: 'Aliyun (需实例 ID)' },
      { value: 'custom', label: '自定义 URL' },
    ],
  })

  if (!Array.isArray(choices)) return

  const mirrorMap: Record<string, string> = {
    dockerproxy: 'https://dockerproxy.cn',
    'one-ms': 'https://docker.1ms.run',
    xuanyuan: 'https://docker.xuanyuan.me',
    netease: 'https://hub-mirror.c.163.com',
    baidu: 'https://mirror.baidubce.com',
    tencent: 'https://ccr.ccs.tencentyun.com',
  }

  const mirrors: string[] = []
  for (const item of choices) {
    if (typeof item !== 'string') continue
    if (item === 'aliyun') {
      const id = await input({ message: 'Aliyun 容器镜像服务实例 ID' })
      if (typeof id === 'string' && id.trim()) mirrors.push(`https://${id.trim()}.mirror.aliyuncs.com`)
    } else if (item === 'custom') {
      const customInput = await input({ message: '自定义镜像 URL（空格分隔）' })
      if (typeof customInput === 'string' && customInput.trim()) {
        for (const url of customInput.trim().split(/\s+/)) {
          if (url) mirrors.push(url)
        }
      }
    } else if (mirrorMap[item]) {
      mirrors.push(mirrorMap[item])
    }
  }

  let cfg: Record<string, unknown> = {}
  try {
    cfg = JSON.parse(fs.readFileSync(DAEMON_JSON, 'utf-8'))
  } catch {}
  const oldMirrors = (cfg['registry-mirrors'] as string[]) || []
  if (JSON.stringify(oldMirrors) === JSON.stringify(mirrors)) {
    logInfo('镜像配置未变化，跳过重启')
    return
  }

  cfg['registry-mirrors'] = mirrors
  const tmpFile = '/tmp/rinbake-daemon.json'
  fs.writeFileSync(tmpFile, JSON.stringify(cfg, null, 2) + '\n')
  await $`sudo mv ${tmpFile} ${DAEMON_JSON}`.nothrow()
  logInfo(`daemon.json 已写入 ${DAEMON_JSON}`)

  logStep('重启 Docker...')
  await $`sudo systemctl restart docker`.nothrow()

  const info = (await $`docker info`).stdout.toString()
  if (info.includes('Registry Mirrors')) {
    logInfo('Docker 镜像配置成功')
  } else {
    logWarn('无法验证镜像配置，请手动检查')
  }

  logInfo('docker-config: 完成')
}

export async function detect(): Promise<boolean> {
  return hasCommand('docker')
}
