import { $ } from 'bun'
import { readFileSync } from 'node:fs'
import { aptInstall, hasCommand, sudoRun } from '../../utils'
import { confirm, input, logInfo, logStep, logWarn } from '../../utils/ui'

export const id = 'orca'
export const label = 'Orca (Agent Development Environment)'
export const description = '安装 Orca AppImage、CLI、Agent hooks、skills 与无头服务'
export const category = 'agent' as const
export const scope = 'system' as const
export const enabled = false

export const ORCA_INSTALL_DIR = '/opt/orca'
export const ORCA_APPIMAGE = `${ORCA_INSTALL_DIR}/orca-linux.AppImage`
export const ORCA_SERVICE = '/etc/systemd/system/orca-serve.service'

export interface OrcaServiceOptions {
  port: number
  pairingAddress?: string
  serviceUser?: string
  serviceHome?: string
}

export function selectOrcaAsset(arch: string): string {
  if (arch === 'x86_64' || arch === 'amd64') return 'orca-linux.AppImage'
  if (arch === 'aarch64' || arch === 'arm64') return 'orca-linux-arm64.AppImage'
  throw new Error(`Orca 不支持当前架构: ${arch}`)
}

export function buildOrcaServiceUnit(options: OrcaServiceOptions): string {
  const user = options.serviceUser || 'orca'
  const home = options.serviceHome || `/home/${user}`
  if (options.pairingAddress?.includes('\n') || options.pairingAddress?.includes('\r')) {
    throw new Error('Orca pairing address 需为单行文本')
  }
  const pairingAddress = options.pairingAddress?.trim().replace(/%/g, '%%')
  const pairing = options.pairingAddress?.trim()
    ? ` --pairing-address ${pairingAddress}`
    : ''

  return `[Unit]
Description=Orca runtime server
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=${user}
WorkingDirectory=${home}
Environment=HOME=${home}
Environment=LIBGL_ALWAYS_SOFTWARE=1
ExecStart=${ORCA_APPIMAGE} serve --port ${options.port}${pairing} --json
KillMode=mixed
Restart=on-failure
RestartPreventExitStatus=3
RestartSec=5

[Install]
WantedBy=multi-user.target
`
}

function isUbuntu24OrNewer(): boolean {
  try {
    const text = readFileSync('/etc/os-release', 'utf8')
    const match = text.match(/^VERSION_ID="?(\d+)\.(\d+)/m)
    return text.includes('ID=ubuntu') && !!match && Number(match[1]) >= 24
  } catch {
    return false
  }
}

async function installRuntimeDependencies(): Promise<void> {
  const renamed = isUbuntu24OrNewer()
  const packages = [
    'curl', 'file', 'jq', 'xvfb', 'zlib1g-dev', 'ca-certificates', 'git',
    renamed ? 'libgtk-3-0t64' : 'libgtk-3-0',
    'libnss3', renamed ? 'libatk1.0-0t64' : 'libatk1.0-0',
    renamed ? 'libatk-bridge2.0-0t64' : 'libatk-bridge2.0-0', 'libgbm1',
    renamed ? 'libasound2t64' : 'libasound2',
    'libxtst6', renamed ? 'libcups2t64' : 'libcups2', 'libdrm2', 'libxkbcommon0',
    'libpango-1.0-0', 'libcairo2', renamed ? 'libatspi2.0-0t64' : 'libatspi2.0-0',
    'libxcomposite1', 'libxdamage1', 'libxfixes3', 'libxrandr2', 'libxrender1',
    'libx11-xcb1', 'libxcb-dri3-0', 'libxss1', renamed ? 'libfuse2t64' : 'libfuse2',
  ]
  if (!(await aptInstall(...packages))) throw new Error('Orca 运行依赖安装失败')
}

async function installAppImage(): Promise<void> {
  const asset = selectOrcaAsset(process.arch)
  const staged = `${ORCA_APPIMAGE}.new`
  const mkdir = await sudoRun(`mkdir -p ${ORCA_INSTALL_DIR}`)
  if (mkdir.exitCode !== 0) throw new Error(`创建 Orca 安装目录失败: ${mkdir.stderr}`)

  logStep(`下载 Orca ${asset}...`)
  const download = await sudoRun(`curl -fL --retry 3 https://github.com/stablyai/orca/releases/latest/download/${asset} -o ${staged}`)
  if (download.exitCode !== 0) throw new Error(`Orca 下载失败: ${download.stderr}`)

  const fileCheck = await sudoRun(`file ${staged}`)
  if (fileCheck.exitCode !== 0 || !/ELF .* executable/i.test(fileCheck.stdout)) {
    throw new Error(`Orca AppImage 文件校验失败: ${fileCheck.stdout || fileCheck.stderr}`)
  }

  const promote = await sudoRun(`chmod 755 ${staged} && mv -f ${staged} ${ORCA_APPIMAGE}`)
  if (promote.exitCode !== 0) throw new Error(`发布 Orca AppImage 失败: ${promote.stderr}`)

  const extracted = `${ORCA_INSTALL_DIR}/squashfs-root/resources/bin/orca-ide`
  const exists = await sudoRun(`test -x ${extracted}`)
  if (exists.exitCode !== 0) {
    const unpack = await sudoRun(`cd ${ORCA_INSTALL_DIR} && ${ORCA_APPIMAGE} --appimage-extract && chmod -R a+rX ${ORCA_INSTALL_DIR}/squashfs-root`)
    if (unpack.exitCode !== 0) throw new Error(`解压 Orca AppImage 失败: ${unpack.stderr}`)
  }

  const link = await sudoRun(`ln -sfn ${extracted} /usr/local/bin/orca-ide`)
  if (link.exitCode !== 0) throw new Error(`注册 orca-ide 失败: ${link.stderr}`)
  logInfo('Orca AppImage 与 orca-ide CLI 已安装')
}

async function runOrca(args: string[]): Promise<{ exitCode: number; stdout: string; stderr: string }> {
  const command = (await hasCommand('orca-ide')) ? 'orca-ide' : ORCA_APPIMAGE
  const proc = Bun.spawn([command, ...args], { stdout: 'pipe', stderr: 'pipe' })
  const exitCode = await proc.exited
  return {
    exitCode,
    stdout: await new Response(proc.stdout).text(),
    stderr: await new Response(proc.stderr).text(),
  }
}

async function configureHooksAndSkills(): Promise<void> {
  const hooks = await runOrca(['agent', 'hooks', 'on', '--json'])
  if (hooks.exitCode !== 0) {
    logWarn(`Orca Agent hooks 配置失败: ${hooks.stderr.trim() || hooks.stdout.trim()}`)
  } else {
    logInfo('Orca Agent hooks 已启用')
    const status = await runOrca(['agent', 'hooks', 'status', '--json'])
    if (status.exitCode !== 0) {
      logWarn(`Orca Agent hooks 状态检查失败: ${status.stderr.trim() || status.stdout.trim()}`)
    } else {
      logInfo('Orca Agent hooks 状态已验证')
    }
  }

  const agents: string[] = []
  if (await hasCommand('claude')) agents.push('claude-code')
  if (await hasCommand('codex')) agents.push('codex')
  if (await hasCommand('opencode')) agents.push('opencode')
  if (await hasCommand('pi')) agents.push('pi')
  if (agents.length === 0) {
    logWarn('未检测到 Claude/Codex/OpenCode/Pi，跳过 Orca skill 安装')
    return
  }

  const installSkill = await confirm({
    message: `为 ${agents.join(', ')} 安装 Orca CLI skill？`,
    defaultValue: true,
  })
  if (installSkill !== true) return

  const skills = await runOrca(['skills', 'install', '--skill', 'orca-cli', '--agent', agents.join(',')])
  if (skills.exitCode !== 0) {
    logWarn(`Orca skill 安装失败: ${skills.stderr.trim() || skills.stdout.trim()}`)
  } else {
    logInfo('Orca CLI skill 已安装')
  }
}

async function configureService(): Promise<void> {
  const enable = await confirm({ message: '生成并启用 Orca 无头 systemd 服务？', defaultValue: true })
  if (enable !== true) return

  const portValue = await input({ message: 'Orca 服务端口', defaultValue: '6768' })
  const parsedPort = typeof portValue === 'string' ? Number.parseInt(portValue.trim(), 10) : Number.NaN
  const port = Number.isInteger(parsedPort) && parsedPort > 0 && parsedPort < 65536 ? parsedPort : 6768
  const pairing = await input({ message: 'Orca pairing address（可留空）', placeholder: '例如 100.64.1.20 或 https://orca.example.com/runtime' })
  const pairingAddress = typeof pairing === 'string' && pairing.trim() ? pairing.trim() : undefined

  const user = 'orca'
  const addUser = await sudoRun(`id -u ${user}`)
  if (addUser.exitCode !== 0) {
    const created = await sudoRun(`useradd --system --create-home --shell /usr/sbin/nologin ${user}`)
    if (created.exitCode !== 0) throw new Error(`创建 Orca 服务用户失败: ${created.stderr}`)
  }

  const unit = buildOrcaServiceUnit({ port, pairingAddress, serviceUser: user, serviceHome: `/home/${user}` })
  const encoded = Buffer.from(unit).toString('base64')
  const write = await sudoRun(`printf %s ${encoded} | base64 -d > ${ORCA_SERVICE}`)
  if (write.exitCode !== 0) throw new Error(`写入 Orca systemd unit 失败: ${write.stderr}`)

  const reload = await sudoRun('systemctl daemon-reload')
  if (reload.exitCode !== 0) throw new Error(`systemd reload 失败: ${reload.stderr}`)
  const start = await confirm({ message: '立即启动 Orca 服务？', defaultValue: true })
  if (start === true) {
    const result = await sudoRun('systemctl enable --now orca-serve.service')
    if (result.exitCode !== 0) throw new Error(`启动 Orca 服务失败: ${result.stderr}`)
    logInfo('Orca 无头服务已启动')
  } else {
    logInfo(`Orca service 已生成: ${ORCA_SERVICE}`)
  }
}

export async function install(): Promise<void> {
  const appImage = (await sudoRun(`test -x ${ORCA_APPIMAGE}`)).exitCode === 0
  if (await hasCommand('orca-ide') && appImage) {
    logStep('Orca CLI 已安装')
  } else {
    await installRuntimeDependencies()
    await installAppImage()
  }
  await configure()
}

export async function configure(): Promise<void> {
  await configureHooksAndSkills()
  await configureService()
  logInfo('orca: 完成')
}

export async function detect(): Promise<boolean> {
  return hasCommand('orca-ide') || hasCommand('orca') || (await sudoRun(`test -x ${ORCA_APPIMAGE}`)).exitCode === 0
}
