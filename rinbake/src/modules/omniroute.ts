import { $ } from 'bun'
import { chmodSync, copyFileSync, existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { hasCommand } from '../utils'
import { input, logInfo, logStep, logWarn, multiselect } from '../utils/ui'
import { promptAndSetKey } from '../config/keys'
import {
  OMNIROUTE_API_KEY,
  OMNIROUTE_DEFAULT_PORT,
  OMNIROUTE_PACKAGE,
  OMNIROUTE_PROVIDER_PRESETS,
  OMNIROUTE_CLIENTS,
  getOmniRouteBaseUrl,
  getOmniRouteClientUrl,
  type OmniRouteClient,
} from '../config/omniroute'

export const id = 'omniroute'
export const label = 'OmniRoute AI Gateway'
export const description = '安装并管理 OmniRoute，配置 Codex、Claude Code、OpenCode 和 Provider'
export const category = 'other' as const
export const enabled = true

const HOME = process.env.HOME || '/root'
const STATE_DIR = join(HOME, '.config/rinbake/omniroute')
const STATE_PATH = join(STATE_DIR, 'config.json')
const PID_PATH = join(STATE_DIR, 'omniroute.pid')
const LOG_PATH = join(STATE_DIR, 'omniroute.log')
const MIGRATION_PATH = join(STATE_DIR, 'legacy-migration.json')
const SKILL_SOURCE = join(import.meta.dir, '../../../skills/omniroute/SKILL.md')

interface OmniRouteState {
  host: string
  port: number
  apiKeyEnv: string
}

export interface OmniRouteStatus {
  installed: boolean
  healthy: boolean
  pid: number | null
  port: number
  dashboardUrl: string
}

function ensureStateDir(): void {
  mkdirSync(STATE_DIR, { recursive: true, mode: 0o700 })
  chmodSync(STATE_DIR, 0o700)
}

function validPort(value: number): boolean {
  return Number.isInteger(value) && value >= 1 && value <= 65535
}

function readState(): OmniRouteState {
  try {
    const parsed = JSON.parse(readFileSync(STATE_PATH, 'utf8')) as Partial<OmniRouteState>
    return {
      host: parsed.host || 'localhost',
      port: validPort(parsed.port as number) ? parsed.port! : OMNIROUTE_DEFAULT_PORT,
      apiKeyEnv: parsed.apiKeyEnv || OMNIROUTE_API_KEY,
    }
  } catch {
    return { host: 'localhost', port: OMNIROUTE_DEFAULT_PORT, apiKeyEnv: OMNIROUTE_API_KEY }
  }
}

function writeState(state: OmniRouteState): void {
  ensureStateDir()
  writeFileSync(STATE_PATH, JSON.stringify(state, null, 2) + '\n', { mode: 0o600 })
  chmodSync(STATE_PATH, 0o600)
}

function readPid(): number | null {
  try {
    const pid = Number.parseInt(readFileSync(PID_PATH, 'utf8').trim(), 10)
    return Number.isInteger(pid) && pid > 0 ? pid : null
  } catch {
    return null
  }
}

function processCommand(pid: number): string {
  try {
    const result = Bun.spawnSync(['ps', '-p', String(pid), '-o', 'command='], { stdout: 'pipe', stderr: 'ignore' })
    return result.stdout.toString().trim()
  } catch {
    return ''
  }
}

function ownsProcess(pid: number): boolean {
  return /(?:^|[\/\s])omniroute(?:\s|$)/i.test(processCommand(pid))
}

async function isHealthy(port = readState().port): Promise<boolean> {
  try {
    const response = await fetch(`${getOmniRouteBaseUrl(port)}/v1/models`, {
      signal: AbortSignal.timeout(800),
    })
    return response.status >= 200 && response.status < 500
  } catch {
    return false
  }
}

async function waitForHealth(port: number, attempts = 20): Promise<boolean> {
  for (let i = 0; i < attempts; i++) {
    if (await isHealthy(port)) return true
    await Bun.sleep(250)
  }
  return false
}

async function installSkill(): Promise<void> {
  if (!(await Bun.file(SKILL_SOURCE).exists())) {
    logWarn(`OmniRoute skill 未找到: ${SKILL_SOURCE}`)
    return
  }
  const content = await Bun.file(SKILL_SOURCE).text()
  for (const target of [
    join(HOME, '.codex/skills/omniroute/SKILL.md'),
    join(HOME, '.claude/skills/omniroute/SKILL.md'),
  ]) {
    mkdirSync(dirname(target), { recursive: true, mode: 0o700 })
    await Bun.write(target, content)
    logInfo(`OmniRoute skill 已安装: ${target}`)
  }
}

export async function install(): Promise<void> {
  ensureStateDir()
  if (await hasCommand(OMNIROUTE_PACKAGE)) {
    logStep('OmniRoute 已安装')
  } else {
    logStep('安装 OmniRoute...')
    const result = await $`npm install -g ${OMNIROUTE_PACKAGE}`.nothrow()
    if (result.exitCode !== 0) throw new Error(`OmniRoute 安装失败 (${result.exitCode})`)
  }
  writeState(readState())
  await installSkill()
  if (!(await isHealthy())) await startService()
  await migrateLegacyConfigs()
  logInfo('OmniRoute 安装完成')
}

/** Ensure the local gateway exists and is accepting requests. */
export async function ensureReady(): Promise<void> {
  if (!(await hasCommand(OMNIROUTE_PACKAGE))) {
    await install()
    return
  }
  if (!(await isHealthy())) await startService()
  await migrateLegacyConfigs()
}

/** Back up and rewrite known legacy relay references without exposing secrets. */
export async function migrateLegacyConfigs(): Promise<void> {
  if (existsSync(MIGRATION_PATH)) return

  const files = [
    join(HOME, '.codex/config.toml'),
    join(HOME, '.claude/settings.json'),
    join(HOME, '.config/opencode/opencode.json'),
    join(HOME, '.pi/agent/settings.json'),
    join(HOME, '.omp/agent/settings.json'),
  ]
  const existing = files.filter(existsSync)
  if (existing.length === 0) {
    ensureStateDir()
    writeFileSync(MIGRATION_PATH, JSON.stringify({ version: 1, files: [] }) + '\n', { mode: 0o600 })
    return
  }

  const stamp = new Date().toISOString().replace(/[:.]/g, '-')
  const backupDir = join(HOME, '.config/rinbake/migrations', stamp)
  mkdirSync(backupDir, { recursive: true, mode: 0o700 })
  const migrated: string[] = []

  for (const file of existing) {
    const original = readFileSync(file, 'utf8')
    const isClaude = file.endsWith('.claude/settings.json')
    const endpoint = getOmniRouteClientUrl(isClaude ? 'claude-code' : 'opencode')
    const backupName = file.replace(/^\//, '').replaceAll('/', '__')
    copyFileSync(file, join(backupDir, backupName))
    const updated = original
      .replaceAll('https://openrouter.ai/api/v1', endpoint)
      .replaceAll('https://aihubmix.com/v1', endpoint)
      .replaceAll('OPENROUTER_API_KEY', OMNIROUTE_API_KEY)
      .replaceAll('AIHUBMIX_API_KEY', OMNIROUTE_API_KEY)
      .replaceAll('openrouter/', 'omniroute/')
      .replaceAll('aihubmix/', 'omniroute/')
      .replaceAll('"openrouter"', '"omniroute"')
      .replaceAll('"aihubmix"', '"omniroute"')
      .replaceAll('custom-relay', 'omniroute')
    if (updated !== original) {
      writeFileSync(file, updated)
      migrated.push(file)
    }
  }

  ensureStateDir()
  writeFileSync(MIGRATION_PATH, JSON.stringify({ version: 1, backupDir, files: migrated }, null, 2) + '\n', { mode: 0o600 })
  chmodSync(MIGRATION_PATH, 0o600)
  logInfo(`旧中转配置已备份: ${backupDir}`)
}

export async function update(): Promise<void> {
  const result = await $`npm install -g ${OMNIROUTE_PACKAGE}@latest`.nothrow()
  if (result.exitCode !== 0) throw new Error(`OmniRoute 更新失败 (${result.exitCode})`)
  await installSkill()
  logInfo('OmniRoute 已更新')
}

export async function configure(): Promise<void> {
  ensureStateDir()
  const current = readState()
  const portInput = await input({ message: 'OmniRoute 端口', defaultValue: String(current.port) })
  const candidatePort = typeof portInput === 'string' && /^\d+$/.test(portInput.trim())
    ? Number(portInput.trim())
    : current.port
  const port = validPort(candidatePort)
    ? candidatePort
    : current.port
  writeState({ host: current.host, port, apiKeyEnv: OMNIROUTE_API_KEY })

  await promptAndSetKey(OMNIROUTE_API_KEY, 'OmniRoute API Key（可留空，取决于本地服务鉴权设置）')
  await installSkill()
  if (!(await isHealthy(port))) await startService()

  const clientSelection = await multiselect({
    message: '选择要交给 OmniRoute 配置的客户端',
    options: Object.entries(OMNIROUTE_CLIENTS).map(([value, def]) => ({
      value,
      label: def.label,
      hint: getOmniRouteClientUrl(value as OmniRouteClient, port),
      checked: true,
    })),
    required: false,
  })
  const clients = Array.isArray(clientSelection)
    ? clientSelection.filter((value): value is string => typeof value === 'string')
    : []
  for (const client of clients) {
    if (client in OMNIROUTE_CLIENTS) await configureClient(client as OmniRouteClient)
  }

  logInfo(`Dashboard: ${getOmniRouteBaseUrl(port)}`)
  logInfo('Provider（包括 chatgpt-web）请在 Dashboard → Providers 中连接；Agent skill 已提供引导 Prompt')
}

export async function configureClient(client: OmniRouteClient): Promise<number> {
  if (!(await hasCommand(OMNIROUTE_PACKAGE))) {
    logWarn('OmniRoute 尚未安装，请先运行: rinbake install omniroute')
    return 1
  }
  const result = Bun.spawnSync(['omniroute', 'configure', client === 'claude-code' ? 'claude' : client], {
    stdin: 'inherit', stdout: 'inherit', stderr: 'inherit',
  })
  if (result.exitCode !== 0) {
    logWarn(`OmniRoute 客户端配置失败: ${client}`)
    return result.exitCode
  }
  logInfo(`${OMNIROUTE_CLIENTS[client].label} 已交给 OmniRoute 配置`)
  return 0
}

export async function startService(): Promise<void> {
  ensureStateDir()
  if (!(await hasCommand(OMNIROUTE_PACKAGE))) {
    throw new Error('OmniRoute 尚未安装，请先运行: rinbake install omniroute')
  }
  const state = readState()
  if (await isHealthy(state.port)) {
    logInfo(`OmniRoute 已运行: ${getOmniRouteBaseUrl(state.port)}`)
    return
  }

  const args = state.port === OMNIROUTE_DEFAULT_PORT ? [] : ['--port', String(state.port)]
  const logFile = Bun.file(LOG_PATH)
  const child = Bun.spawn(['omniroute', ...args], {
    stdin: 'ignore',
    stdout: logFile,
    stderr: logFile,
    detached: true,
  })
  writeFileSync(PID_PATH, `${child.pid}\n`, { mode: 0o600 })
  chmodSync(PID_PATH, 0o600)
  ;(child as unknown as { unref?: () => void }).unref?.()

  if (!(await waitForHealth(state.port))) {
    if (ownsProcess(child.pid)) process.kill(child.pid, 'SIGTERM')
    try { unlinkSync(PID_PATH) } catch {}
    throw new Error(`OmniRoute 未能在 ${getOmniRouteBaseUrl(state.port)} 启动，请查看 ${LOG_PATH}`)
  }
  logInfo(`OmniRoute 已启动: ${getOmniRouteBaseUrl(state.port)}`)
}

export async function stopService(): Promise<void> {
  const pid = readPid()
  if (!pid) {
    logInfo('没有由 rinbake 记录的 OmniRoute 进程')
    return
  }
  if (ownsProcess(pid)) {
    process.kill(pid, 'SIGTERM')
    for (let i = 0; i < 20 && ownsProcess(pid); i++) await Bun.sleep(100)
    logInfo(`OmniRoute 已停止: PID ${pid}`)
  } else {
    logWarn(`PID ${pid} 已不是 OmniRoute，未执行 kill`)
  }
  try { unlinkSync(PID_PATH) } catch {}
}

export async function restartService(): Promise<void> {
  await stopService()
  await startService()
}

export async function getStatus(): Promise<OmniRouteStatus> {
  const state = readState()
  return {
    installed: await hasCommand(OMNIROUTE_PACKAGE),
    healthy: await isHealthy(state.port),
    pid: readPid(),
    port: state.port,
    dashboardUrl: getOmniRouteBaseUrl(state.port),
  }
}

export async function status(): Promise<OmniRouteStatus> {
  const current = await getStatus()
  logInfo(`OmniRoute: ${current.installed ? '已安装' : '未安装'}`)
  logInfo(`服务: ${current.healthy ? 'healthy' : 'offline'} (${current.dashboardUrl})`)
  logInfo(`PID: ${current.pid ?? 'none'}`)
  return current
}

export async function doctor(): Promise<number> {
  if (!(await hasCommand(OMNIROUTE_PACKAGE))) {
    logWarn('OmniRoute 尚未安装，请先运行: rinbake install omniroute')
    return 1
  }
  const result = Bun.spawnSync(['omniroute', 'doctor'], { stdin: 'inherit', stdout: 'inherit', stderr: 'inherit' })
  return result.exitCode
}

export async function showLogs(): Promise<void> {
  if (!(await Bun.file(LOG_PATH).exists())) {
    logInfo(`暂无日志: ${LOG_PATH}`)
    return
  }
  const lines = (await Bun.file(LOG_PATH).text()).split(/\r?\n/)
  console.log(lines.slice(-100).join('\n'))
}

export async function openDashboard(): Promise<void> {
  const url = getOmniRouteBaseUrl(readState().port)
  const command = process.platform === 'darwin' ? 'open' : 'xdg-open'
  try {
    const result = Bun.spawnSync([command, url], { stdin: 'ignore', stdout: 'ignore', stderr: 'ignore' })
    if (result.exitCode !== 0) logInfo(`请手动打开: ${url}`)
    else logInfo(`已打开: ${url}`)
  } catch {
    logInfo(`请手动打开: ${url}`)
  }
}

export function listProviderPresets(): void {
  logInfo('OmniRoute Provider 预设:')
  for (const provider of OMNIROUTE_PROVIDER_PRESETS) {
    logInfo(`  ${provider.id}: ${provider.label} · ${provider.auth}${provider.manualAuth ? ' · 需要 Dashboard/浏览器授权' : ''}`)
  }
  logInfo('动态 Provider 与模型以 OmniRoute Dashboard 为准')
}

export async function detect(): Promise<boolean> {
  return (await hasCommand(OMNIROUTE_PACKAGE)) && (await isHealthy())
}
