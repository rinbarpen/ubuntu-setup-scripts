import { $ } from 'bun'
import { hasCommand, targetHome } from '../../utils'
import { confirm, input, logInfo, logStep, select } from '../../utils/ui'

export const id = 'paseo'
export const label = 'Paseo (Agent Orchestration)'
export const description = '安装 Paseo CLI + daemon 配置 + MCP'
export const category = 'agent' as const
export const scope = 'user' as const
export const enabled = true

export interface PaseoConfigOptions {
  listen: string
  mcpEnabled: boolean
  injectIntoAgents: boolean
  relayEnabled: boolean
  hostname?: string
}

export function paseoHostnames(listen: string, hostname = 'localhost'): string[] {
  const host = listen.trim().replace(/^\[|\]$/g, '').split(':')[0]
  if (host === '0.0.0.0' || host === '::') {
    return ['localhost', '.localhost', hostname, `.${hostname}`]
  }
  return ['localhost', '.localhost']
}

export function mergePaseoConfig(
  current: Record<string, unknown>,
  options: PaseoConfigOptions,
): Record<string, unknown> {
  const daemon = current.daemon && typeof current.daemon === 'object'
    ? { ...(current.daemon as Record<string, unknown>) }
    : {}
  const mcp = daemon.mcp && typeof daemon.mcp === 'object'
    ? { ...(daemon.mcp as Record<string, unknown>) }
    : {}
  const relay = daemon.relay && typeof daemon.relay === 'object'
    ? { ...(daemon.relay as Record<string, unknown>) }
    : {}

  daemon.listen = options.listen
  daemon.hostnames = paseoHostnames(options.listen, options.hostname || 'localhost')
  daemon.mcp = {
    ...mcp,
    enabled: options.mcpEnabled,
    injectIntoAgents: options.injectIntoAgents,
  }
  daemon.relay = { ...relay, enabled: options.relayEnabled }

  return {
    ...current,
    '$schema': 'https://paseo.sh/schemas/paseo.config.v1.json',
    version: 1,
    daemon,
  }
}

function configPath(): string {
  return `${targetHome()}/.paseo/config.json`
}

async function readPaseoConfig(): Promise<Record<string, unknown>> {
  const file = Bun.file(configPath())
  if (!(await file.exists())) return {}
  try {
    const parsed = JSON.parse(await file.text())
    return parsed && typeof parsed === 'object' ? parsed : {}
  } catch {
    return {}
  }
}

function currentDaemonValue(config: Record<string, unknown>, key: string): unknown {
  const daemon = config.daemon
  return daemon && typeof daemon === 'object' ? (daemon as Record<string, unknown>)[key] : undefined
}

async function choosePaseoOptions(config: Record<string, unknown>): Promise<PaseoConfigOptions> {
  const currentListen = typeof currentDaemonValue(config, 'listen') === 'string'
    ? currentDaemonValue(config, 'listen') as string
    : '127.0.0.1:6767'
  const listenChoice = await select({
    message: 'Paseo daemon 监听地址',
    options: [
      { value: 'local', label: '本机监听', hint: `127.0.0.1:6767（当前: ${currentListen}）` },
      { value: 'all', label: '所有网卡', hint: '0.0.0.0:6767' },
      { value: 'custom', label: '自定义地址', hint: '例如 127.0.0.1:6799' },
    ],
  })

  let listen = currentListen
  if (listenChoice === 'local') listen = '127.0.0.1:6767'
  if (listenChoice === 'all') listen = '0.0.0.0:6767'
  if (listenChoice === 'custom') {
    const value = await input({ message: '输入 Paseo daemon 监听地址', defaultValue: currentListen })
    if (typeof value === 'string' && value.trim()) listen = value.trim()
  }

  const mcp = currentDaemonValue(config, 'mcp')
  const currentMcp = mcp && typeof mcp === 'object' ? mcp as Record<string, unknown> : {}
  const relay = currentDaemonValue(config, 'relay')
  const currentRelay = relay && typeof relay === 'object' ? relay as Record<string, unknown> : {}

  const mcpEnabled = await confirm({
    message: '启用 Paseo MCP server？',
    defaultValue: currentMcp.enabled !== false,
  })
  const injectIntoAgents = await confirm({
    message: '将 Paseo MCP 工具注入 Paseo 启动的 Agent？',
    defaultValue: currentMcp.injectIntoAgents === true,
  })
  const relayEnabled = await confirm({
    message: '启用 Paseo relay？',
    defaultValue: currentRelay.enabled === true,
  })

  return {
    listen,
    mcpEnabled: mcpEnabled === true,
    injectIntoAgents: injectIntoAgents === true,
    relayEnabled: relayEnabled === true,
    hostname: process.env.HOSTNAME?.trim() || 'localhost',
  }
}

async function writeShellHelpers(): Promise<void> {
  const home = targetHome()
  const fishDir = `${home}/.config/fish/functions`
  await $`mkdir -p ${fishDir}`.nothrow()
  await Bun.write(`${fishDir}/paseo_daemon.fish`, `function paseo-daemon
    set -l args daemon start
    if test -n "$PASEO_HOME"
        set -a args --home "$PASEO_HOME"
    end
    paseo $args $argv
end
`)

  const bashrc = `${home}/.bashrc`
  const file = Bun.file(bashrc)
  const text = (await file.exists()) ? await file.text() : ''
  const marker = '# paseo-daemon (added by rinbake)'
  if (!text.includes(marker)) {
    await Bun.write(bashrc, `${text}
${marker}
paseo-daemon() {
  local args=("daemon" "start")
  if [[ -n "\${PASEO_HOME:-}" ]]; then args+=(--home "\${PASEO_HOME}"); fi
  paseo "\${args[@]}" "$@"
}
`)
  }
}

export async function install(): Promise<void> {
  if (await hasCommand('paseo')) {
    logStep('Paseo 已安装')
  } else {
    logStep('安装 Paseo...')
    const result = await $`npm install -g @getpaseo/cli --ignore-scripts`.nothrow()
    if (result.exitCode !== 0) throw new Error(`Paseo 安装失败 (${result.exitCode})`)
  }

  await configure()
  logInfo('paseo: 完成')
}

export async function configure(): Promise<void> {
  const path = configPath()
  const dir = path.replace(/\/[^/]+$/, '')
  await $`mkdir -p ${dir}`.nothrow()

  const current = await readPaseoConfig()
  const options = await choosePaseoOptions(current)
  const merged = mergePaseoConfig(current, options)
  await Bun.write(path, JSON.stringify(merged, null, 2) + '\n')
  await writeShellHelpers()

  logInfo(`Paseo 配置已写入 ${path}`)
  logInfo('如需设置 daemon 密码，请运行: paseo daemon set-password')
}

export async function detect(): Promise<boolean> {
  return hasCommand('paseo')
}
