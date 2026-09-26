import { $ } from 'bun'
import { hasCommand } from '../../utils'
import { logStep, logInfo, logWarn, select, input, confirm, multiselect } from '../../utils/ui'
import { readConfig, writeConfig, writeMcpConfig } from '../../config/manager'
import { promptAndSetKey } from '../../config/keys'
import { getMcpServers } from '../mcp'
import { configureClient, ensureReady } from '../omniroute'
import { getOmniRouteClientUrl, OMNIROUTE_API_KEY } from '../../config/omniroute'

export const id = 'opencode'
export const label = 'opencode CLI + MCP'
export const description = '安装 opencode-ai 并通过 OmniRoute 配置模型、MCP 服务器'
export const category = 'agent' as const
export const enabled = true

export async function install(): Promise<void> {
  if (await hasCommand('opencode')) {
    logStep('opencode 已安装')
  } else {
    logStep('安装 opencode...')
    await $`npm install -g opencode-ai`.nothrow()
  }

  await configure()
}

export async function configure(): Promise<void> {
  await ensureReady()
  await configureClient('opencode')

  const cfgPath = `${process.env.HOME || '/root'}/.config/opencode/opencode.json`
  const cfgDir = cfgPath.replace(/\/[^/]+$/, '')
  await $`mkdir -p ${cfgDir}`.nothrow()

  let config: Record<string, unknown> = {}
  try {
    const f = Bun.file(cfgPath)
    if (await f.exists()) config = JSON.parse(await f.text())
  } catch {}

  // Model selection
  const modelOption = await select({
    message: '选择默认模型',
    options: [
      { value: 'omniroute/auto', label: 'OmniRoute Auto', hint: 'Dashboard 路由' },
      { value: 'omniroute/auto/coding', label: 'OmniRoute Coding' },
      { value: 'omniroute/auto/fast', label: 'OmniRoute Fast' },
      { value: 'deepseek/deepseek-v4-flash', label: 'DeepSeek V4 Flash', hint: '直连 API' },
      { value: 'deepseek/deepseek-v4-pro', label: 'DeepSeek V4 Pro', hint: '直连 API' },
      { value: 'openai/gpt-5.5', label: 'OpenAI GPT-5.5' },
      { value: 'openai/gpt-4o', label: 'OpenAI GPT-4o' },
      { value: 'custom', label: '自定义模型' },
    ],
  })

  let defaultModel = 'omniroute/auto'
  if (typeof modelOption === 'string') {
    if (modelOption === 'custom') {
      const custom = await input({ message: '输入模型 (provider/model)' })
      if (typeof custom === 'string' && custom.trim()) defaultModel = custom.trim()
    } else {
      defaultModel = modelOption
    }
  }

  // Plan model
  const planOption = await select({
    message: '选择 Plan 模型',
    options: [
      { value: 'omniroute/auto', label: 'OmniRoute Auto', hint: '默认' },
      { value: 'omniroute/auto/coding', label: 'OmniRoute Coding' },
      { value: 'omniroute/auto/fast', label: 'OmniRoute Fast' },
      { value: 'openai/gpt-5.5', label: 'OpenAI GPT-5.5', hint: '直连 API' },
      { value: 'openai/gpt-4o', label: 'OpenAI GPT-4o' },
      { value: 'deepseek/deepseek-reasoner', label: 'DeepSeek Reasoner', hint: '直连 API' },
      { value: 'custom', label: '自定义' },
    ],
  })
  let planModel = 'omniroute/auto'
  if (typeof planOption === 'string') {
    if (planOption === 'custom') {
      const c = await input({ message: '输入 Plan 模型' })
      if (typeof c === 'string' && c.trim()) planModel = c.trim()
    } else {
      planModel = planOption
    }
  }

  await promptAndSetKey('DEEPSEEK_API_KEY', 'DeepSeek API Key')

  // MCP servers
  const mcpSelection = await selectMcpServers()
  const mcpNeeded = mcpSelection.filter(s => s.selected)
  const mcpMap = getMcpServers(mcpNeeded.map(s => s.id))
  const keysNeededForMcp = collectMcpKeys(mcpNeeded)

  for (const key of keysNeededForMcp) {
    await promptAndSetKey(key.envVar, key.label)
  }

  // Write config
  config['$schema'] = 'https://opencode.ai/config.json'
  config.model = defaultModel

  const provider: Record<string, unknown> = (config.provider as Record<string, unknown>) || {}
  provider.omniroute = {
    npm: '@ai-sdk/openai',
    options: { apiKey: `{env:${OMNIROUTE_API_KEY}}`, baseURL: getOmniRouteClientUrl('opencode') },
  }
  provider.deepseek = {
    npm: '@ai-sdk/deepseek',
    options: { apiKey: '{env:DEEPSEEK_API_KEY}' },
  }

  provider.openai = { npm: '@ai-sdk/openai', options: { apiKey: '{env:OPENAI_API_KEY}' } }

  config.provider = provider
  config.agent = {
    plan: {
      model: planModel,
      options: { reasoningEffort: 'xhigh' },
    },
  }
  config.permission = { edit: 'ask', bash: 'ask', external_directory: 'ask' }

  // MCP section
  const mcpServers: Record<string, unknown> = {}
  for (const [name, def] of Object.entries(mcpMap)) {
    const entry: Record<string, unknown> = { type: 'local', command: def.command, enabled: true }
    if (def.args) entry.args = def.args
    if (def.env) entry.environment = def.env
    mcpServers[name] = entry
  }
  if (Object.keys(mcpServers).length > 0) config.mcp = mcpServers

  await $`mkdir -p ${cfgDir}`.nothrow()
  await Bun.write(cfgPath, JSON.stringify(config, null, 2) + '\n')
  logInfo(`opencode 配置已写入 ${cfgPath}`)
}

async function selectMcpServers(): Promise<{ id: string; selected: boolean }[]> {
  const allServers = getMcpServers([])
  const allOptions = Object.entries(allServers).map(([id, def]) => ({
    value: id,
    label: def.name,
    hint: def.command,
    checked: false,
  }))

  // Pre-select daily + chat scenarios as sensible defaults
  const defaultSelected = new Set(['context7', 'brave-search'])
  for (const opt of allOptions) {
    if (defaultSelected.has(opt.value)) opt.checked = true
  }

  const result = await multiselect({
    message: '选择 MCP 服务器（Space 切换, Enter 确认）',
    options: allOptions,
  })

  const selected = Array.isArray(result)
    ? result.filter((v): v is string => typeof v === 'string')
    : []

  return Object.keys(allServers).map(id => ({
    id,
    selected: selected.includes(id),
  }))
}

function collectMcpKeys(servers: { id: string; selected: boolean }[]): { envVar: string; label: string }[] {
  const needed: { envVar: string; label: string }[] = []
  for (const s of servers) {
    if (!s.selected) continue
    if (s.id === 'brave-search') needed.push({ envVar: 'BRAVE_API_KEY', label: 'Brave API Key' })
    if (s.id === 'github') needed.push({ envVar: 'GITHUB_TOKEN', label: 'GitHub Personal Access Token' })
    if (s.id === 'postgres') needed.push({ envVar: 'POSTGRES_DSN', label: 'Postgres 连接字符串' })
  }
  return needed
}

export async function detect(): Promise<boolean> {
  return hasCommand('opencode')
}
