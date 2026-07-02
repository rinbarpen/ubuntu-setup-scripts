import { $ } from 'bun'
import { hasCommand } from '../../utils'
import { logStep, logInfo, logWarn, select, input, confirm, multiselect } from '../../utils/ui'
import { readConfig, writeConfig, writeMcpConfig } from '../../config/manager'
import { promptAndSetKey } from '../../config/keys'
import { getMcpServers } from '../mcp'

export const id = 'opencode'
export const label = 'opencode CLI + MCP'
export const description = '安装 opencode-ai 并配置模型、MCP 服务器、中转'
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
      { value: 'deepseek/deepseek-v4-flash', label: 'DeepSeek V4 Flash', hint: '快速 & 便宜' },
      { value: 'deepseek/deepseek-v4-pro', label: 'DeepSeek V4 Pro', hint: '更强能力' },
      { value: 'openai/gpt-5.5', label: 'OpenAI GPT-5.5' },
      { value: 'openai/gpt-4o', label: 'OpenAI GPT-4o' },
      { value: 'openrouter/anthropic/claude-sonnet-4-20250514', label: 'Claude Sonnet 4', hint: 'via OpenRouter' },
      { value: 'openrouter/anthropic/claude-opus-4-20250514', label: 'Claude Opus 4', hint: 'via OpenRouter' },
      { value: 'aihubmix/openai/gpt-5.5', label: 'GPT-5.5', hint: 'via AIHubMix' },
      { value: 'custom', label: '自定义模型' },
    ],
  })

  let defaultModel = 'deepseek/deepseek-v4-flash'
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
      { value: 'openai/gpt-5.5', label: 'OpenAI GPT-5.5', hint: '默认' },
      { value: 'openai/gpt-4o', label: 'OpenAI GPT-4o' },
      { value: 'deepseek/deepseek-reasoner', label: 'DeepSeek Reasoner' },
      { value: 'openrouter/anthropic/claude-sonnet-4-20250514', label: 'Claude Sonnet 4', hint: 'via OpenRouter' },
      { value: 'custom', label: '自定义' },
    ],
  })
  let planModel = 'openai/gpt-5.5'
  if (typeof planOption === 'string') {
    if (planOption === 'custom') {
      const c = await input({ message: '输入 Plan 模型' })
      if (typeof c === 'string' && c.trim()) planModel = c.trim()
    } else {
      planModel = planOption
    }
  }

  // Relay
  const relayOption = await select({
    message: '配置中转代理？',
    options: [
      { value: 'none', label: '直接 OpenAI API', hint: '默认' },
      { value: 'openrouter', label: 'OpenRouter', hint: 'https://openrouter.ai/api/v1' },
      { value: 'aihubmix', label: 'AIHubMix', hint: 'https://aihubmix.com/v1' },
      { value: 'custom', label: '自定义中转' },
    ],
  })

  let relayProvider = ''
  let relayBaseUrl = ''
  let relayKeyName = ''
  if (typeof relayOption === 'string' && relayOption !== 'none') {
    if (relayOption === 'openrouter') {
      relayProvider = 'openrouter'
      relayBaseUrl = 'https://openrouter.ai/api/v1'
      relayKeyName = 'OPENROUTER_API_KEY'
      await promptAndSetKey('OPENROUTER_API_KEY', 'OpenRouter API Key')
    } else if (relayOption === 'aihubmix') {
      relayProvider = 'aihubmix'
      relayBaseUrl = 'https://aihubmix.com/v1'
      relayKeyName = 'AIHUBMIX_API_KEY'
      await promptAndSetKey('AIHUBMIX_API_KEY', 'AIHubMix API Key')
    } else if (relayOption === 'custom') {
      relayProvider = 'custom-relay'
      const url = await input({ message: '中转 base URL' })
      if (typeof url === 'string' && url.trim()) relayBaseUrl = url.trim()
      const keyName = await input({ message: 'API Key 环境变量名' })
      if (typeof keyName === 'string' && keyName.trim()) {
        relayKeyName = keyName.trim()
        await promptAndSetKey(relayKeyName, relayKeyName)
      }
    }
  }

  await promptAndSetKey('DEEPSEEK_API_KEY', 'DeepSeek API Key')

  // MCP servers
  const mcpSelection = await selectMcpServers()
  const mcpNeeded = mcpSelection.filter(s => s.selected)
  const mcpMap = getMcpServers(mcpNeeded)
  const keysNeededForMcp = collectMcpKeys(mcpNeeded)

  for (const key of keysNeededForMcp) {
    await promptAndSetKey(key.envVar, key.label)
  }

  // Write config
  config['$schema'] = 'https://opencode.ai/config.json'
  config.model = defaultModel

  const provider: Record<string, unknown> = {}
  provider.deepseek = {
    npm: '@ai-sdk/deepseek',
    options: { apiKey: '{env:DEEPSEEK_API_KEY}' },
  }

  const openaiOpts: Record<string, unknown> = { apiKey: '{env:OPENAI_API_KEY}' }
  if (relayBaseUrl) openaiOpts.baseURL = relayBaseUrl
  provider.openai = { npm: '@ai-sdk/openai', options: openaiOpts }

  if (relayProvider === 'openrouter' || !relayBaseUrl) {
    provider.openrouter = {
      npm: '@ai-sdk/openai',
      options: { apiKey: '{env:OPENROUTER_API_KEY}', baseURL: 'https://openrouter.ai/api/v1' },
    }
  }
  if (relayProvider === 'aihubmix' || !relayBaseUrl) {
    provider.aihubmix = {
      npm: '@ai-sdk/openai',
      options: { apiKey: '{env:AIHUBMIX_API_KEY}', baseURL: 'https://aihubmix.com/v1' },
    }
  }
  if (relayProvider === 'custom-relay' && relayKeyName) {
    provider[relayProvider] = {
      npm: '@ai-sdk/openai',
      options: { apiKey: `{env:${relayKeyName}}`, baseURL: relayBaseUrl },
    }
  }

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
