import { hasCommand } from '../../utils/shell'
import { aptInstall } from '../../utils/sudo'
import { confirm, logInfo, logStep, logWarn } from '../../utils/ui'

export interface AuthStatusEntry {
  host: string
  login: string
  state: string
}

export interface AuthStatus {
  authenticated: boolean
  entries: AuthStatusEntry[]
}

export type GhResult = {
  exitCode: number
  stdout: string
  stderr: string
}

export type InstallDeps = {
  detect: () => Promise<boolean>
  installGh: (pkg: string) => Promise<boolean>
}

export type ConfigureDeps = {
  detect: () => Promise<boolean>
  isTTY: boolean
  confirm: (opts: { defaultValue?: boolean }) => Promise<boolean | symbol>
  runGh: (args: string[], interactive?: boolean) => Promise<GhResult>
  logInfo: (message: string) => void
  logWarn: (message: string) => void
}

const STATUS_ARGS = ['auth', 'status', '--json', 'hosts']
const LOGIN_ARGS = ['auth', 'login']

function parseError(reason: string): Error {
  return new Error(`gh auth status: ${reason}`)
}

export function parseAuthStatus(stdout: string): AuthStatus {
  let parsed: unknown
  try {
    parsed = JSON.parse(stdout)
  } catch {
    throw parseError('invalid JSON')
  }

  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw parseError('invalid top-level object')
  }

  const hosts = (parsed as Record<string, unknown>).hosts
  if (hosts === null || typeof hosts !== 'object' || Array.isArray(hosts)) {
    throw parseError('invalid hosts map')
  }

  const entries: AuthStatusEntry[] = []
  for (const [mapHost, rawEntries] of Object.entries(hosts as Record<string, unknown>)) {
    if (!Array.isArray(rawEntries)) throw parseError('invalid host entries')

    for (const rawEntry of rawEntries) {
      if (rawEntry === null || typeof rawEntry !== 'object' || Array.isArray(rawEntry)) {
        throw parseError('invalid host entry')
      }

      const entry = rawEntry as Record<string, unknown>
      const host = typeof entry.host === 'string' ? entry.host : mapHost
      const login = typeof entry.login === 'string' ? entry.login : ''
      if (typeof entry.state !== 'string') {
        throw parseError('invalid host state')
      }

      entries.push({ host, login, state: entry.state })
    }
  }

  return {
    authenticated: entries.some(entry => entry.state === 'success'),
    entries,
  }
}

export async function detectGithubCli(hasGh: () => Promise<boolean>): Promise<boolean> {
  return hasGh()
}

export function sanitizeDiagnostic(value: string): string {
  return value
    .replace(/\bBearer\s+[A-Za-z0-9._~+\/-]+=*/gi, 'Bearer [redacted]')
    .replace(/\b(?:ghp|gho|ghu|ghs|ghr|github_pat)_[A-Za-z0-9_-]+\b/gi, '[redacted]')
    .replace(/((?:["']?(?:access[_-]?token|oauth[_-]?token|refresh[_-]?token|token|secret|password|authorization)["']?)\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,}]+)/gi, '$1[redacted]')
    .replace(/\bTOKEN\b/gi, '[redacted]')
    .replace(/[\u0000-\u001f\u007f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 160)
}

function safeSummaryValue(value: string): string {
  return sanitizeDiagnostic(value).slice(0, 100)
}

function diagnosticOrFallback(value: string, fallback: string): string {
  return sanitizeDiagnostic(value) || fallback
}

function errorDiagnostic(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error)
  return diagnosticOrFallback(message, 'exception')
}

function resultDiagnostic(result: GhResult): string {
  return diagnosticOrFallback(result.stderr || result.stdout, `exit code ${result.exitCode}`)
}

function authSummary(status: AuthStatus): string {
  if (status.entries.length === 0) return 'no hosts'
  return status.entries
    .map(entry => {
      const host = safeSummaryValue(entry.host)
      const login = entry.login ? safeSummaryValue(entry.login) : '(none)'
      const state = safeSummaryValue(entry.state)
      return `host=${host} login=${login} state=${state}`
    })
    .join('; ')
}

async function defaultRunGh(args: string[], interactive = false): Promise<GhResult> {
  const process = Bun.spawnSync(['gh', ...args], {
    stdin: interactive ? 'inherit' : 'ignore',
    stdout: interactive ? 'inherit' : 'pipe',
    stderr: interactive ? 'inherit' : 'pipe',
  })

  return {
    exitCode: process.exitCode,
    stdout: interactive ? '' : process.stdout.toString(),
    stderr: interactive ? '' : process.stderr.toString(),
  }
}

export async function installGithubCli(deps: InstallDeps): Promise<boolean> {
  let installed: boolean
  try {
    installed = await deps.detect()
  } catch {
    throw new Error('gh detection failed')
  }

  if (installed) {
    logStep('gh 已安装，跳过')
    return true
  }

  let installedByApt: boolean
  try {
    installedByApt = await deps.installGh('gh')
  } catch {
    throw new Error('gh installation failed')
  }
  if (!installedByApt) throw new Error('gh installation failed')

  try {
    installed = await deps.detect()
  } catch {
    throw new Error('gh detection failed after installation')
  }
  if (!installed) throw new Error('gh installation could not be verified')

  logInfo('gh 安装完成')
  return true
}

async function readAuthStatus(
  deps: ConfigureDeps,
): Promise<{ status: AuthStatus } | { failed: 'command' | 'invalid'; detail: string }> {
  let result: GhResult
  try {
    result = await deps.runGh(STATUS_ARGS, false)
  } catch (error) {
    return { failed: 'command', detail: errorDiagnostic(error) }
  }

  if (result.exitCode !== 0) {
    return { failed: 'command', detail: resultDiagnostic(result) }
  }

  try {
    return { status: parseAuthStatus(result.stdout) }
  } catch (error) {
    return { failed: 'invalid', detail: errorDiagnostic(error) }
  }
}

function logAuthStatus(deps: ConfigureDeps, status: AuthStatus): void {
  deps.logInfo(`gh auth status: ${authSummary(status)}`)
}

async function loginAndRecheck(deps: ConfigureDeps): Promise<void> {
  let loginResult: GhResult
  try {
    loginResult = await deps.runGh(LOGIN_ARGS, true)
  } catch (error) {
    deps.logWarn(`gh auth login failed: ${errorDiagnostic(error)}`)
    return
  }

  if (loginResult.exitCode !== 0) {
    deps.logWarn(`gh auth login failed: ${resultDiagnostic(loginResult)}`)
    return
  }

  const checked = await readAuthStatus(deps)
  if ('failed' in checked) {
    deps.logWarn(`gh auth status ${checked.failed === 'invalid' ? 'invalid' : 'failed'} after login: ${checked.detail}`)
    return
  }

  if (checked.status.authenticated) {
    deps.logInfo(`gh auth login completed: ${authSummary(checked.status)}`)
  } else {
    deps.logWarn('gh auth login failed: authentication not confirmed')
  }
}

export async function configureGithubCli(deps: ConfigureDeps): Promise<void> {
  let installed: boolean
  try {
    installed = await deps.detect()
  } catch {
    deps.logWarn('gh detection failed; install GitHub CLI first')
    return
  }

  if (!installed) {
    deps.logInfo('gh 未安装，请先安装 GitHub CLI')
    return
  }

  const checked = await readAuthStatus(deps)
  if ('failed' in checked) {
    deps.logWarn(`gh auth status ${checked.failed === 'invalid' ? 'invalid' : 'failed'}: ${checked.detail}`)
    return
  }

  if (checked.status.authenticated) {
    logAuthStatus(deps, checked.status)
    if (!deps.isTTY) return

    const shouldLogin = await deps.confirm({
      defaultValue: false,
    })
    if (shouldLogin === true) await loginAndRecheck(deps)
    return
  }

  if (!deps.isTTY) {
    deps.logInfo('未完成 GitHub CLI 认证，请运行 gh auth login')
    return
  }

  await loginAndRecheck(deps)
}

export const id = 'github-cli'
export const label = 'GitHub CLI (gh)'
export const description = '安装 GitHub CLI 并完成 GitHub 认证'
export const category = 'system' as const
export const enabled = true

const defaultInstallDeps: InstallDeps = {
  detect: () => detectGithubCli(() => hasCommand('gh')),
  installGh: (pkg: string) => aptInstall(pkg),
}

const defaultConfigureDeps: ConfigureDeps = {
  detect: () => detectGithubCli(() => hasCommand('gh')),
  isTTY: Boolean(process.stdin.isTTY),
  confirm: opts => confirm({
    message: '已有 GitHub CLI 认证，是否重新登录？',
    defaultValue: opts.defaultValue,
  }),
  runGh: defaultRunGh,
  logInfo,
  logWarn,
}

export async function detect(): Promise<boolean> {
  return defaultConfigureDeps.detect()
}

export async function install(): Promise<void> {
  await installGithubCli(defaultInstallDeps)
}

export async function configure(): Promise<void> {
  await configureGithubCli(defaultConfigureDeps)
}
