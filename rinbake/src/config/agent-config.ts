import { select, input, multiselect } from '../utils/ui'
import { promptAndSetKey } from './keys'
import { getMcpServers } from '../modules/mcp'

export interface AgentModelOption {
  value: string
  label: string
  hint?: string
}

export interface AgentProviderDef {
  id: string
  label: string
  hint?: string
  keyEnv: string
  keyLabel: string
}

export const COMMON_MODELS: AgentModelOption[] = [
  { value: 'deepseek/deepseek-v4-flash', label: 'DeepSeek V4 Flash', hint: '快速 & 便宜' },
  { value: 'deepseek/deepseek-v4-pro', label: 'DeepSeek V4 Pro', hint: '更强能力' },
  { value: 'openai/gpt-5.5', label: 'OpenAI GPT-5.5' },
  { value: 'openai/gpt-4o', label: 'OpenAI GPT-4o' },
  { value: 'openrouter/anthropic/claude-sonnet-4-20250514', label: 'Claude Sonnet 4', hint: 'via OpenRouter' },
  { value: 'openrouter/anthropic/claude-opus-4-20250514', label: 'Claude Opus 4', hint: 'via OpenRouter' },
  { value: 'aihubmix/openai/gpt-5.5', label: 'GPT-5.5', hint: 'via AIHubMix' },
  { value: 'custom', label: '自定义模型' },
]

export const COMMON_PROVIDERS: AgentProviderDef[] = [
  { id: 'deepseek',   label: 'DeepSeek',   hint: 'https://api.deepseek.com',              keyEnv: 'DEEPSEEK_API_KEY',   keyLabel: 'DeepSeek API Key' },
  { id: 'openai',     label: 'OpenAI',     hint: 'https://api.openai.com/v1',             keyEnv: 'OPENAI_API_KEY',     keyLabel: 'OpenAI API Key' },
  { id: 'anthropic',  label: 'Anthropic',  hint: '官方 API',                               keyEnv: 'ANTHROPIC_API_KEY',  keyLabel: 'Anthropic API Key' },
  { id: 'openrouter', label: 'OpenRouter', hint: 'https://openrouter.ai/api/v1',          keyEnv: 'OPENROUTER_API_KEY', keyLabel: 'OpenRouter API Key' },
  { id: 'aihubmix',   label: 'AIHubMix',   hint: 'https://aihubmix.com/v1',               keyEnv: 'AIHUBMIX_API_KEY',   keyLabel: 'AIHubMix API Key' },
  { id: 'google',     label: 'Google',     hint: 'Gemini API',                             keyEnv: 'GOOGLE_API_KEY',     keyLabel: 'Google API Key' },
]

export interface SelectModelResult {
  model: string
}

export async function selectAgentModel(opts?: {
  message?: string
  extraModels?: AgentModelOption[]
  defaultModel?: string
}): Promise<string> {
  const message = opts?.message ?? '选择默认模型'
  const extra = opts?.extraModels ?? []
  const models = [...COMMON_MODELS, ...extra.filter(m => m.value !== 'custom')]
  if (!models.some(m => m.value === 'custom')) {
    models.push({ value: 'custom', label: '自定义模型' })
  }

  const result = await select({
    message,
    options: models.map(m => ({ value: m.value, label: m.label, hint: m.hint })),
  })

  if (typeof result !== 'string') return opts?.defaultModel ?? 'deepseek/deepseek-v4-flash'
  if (result === 'custom') {
    const c = await input({ message: '输入模型 (provider/model)' })
    if (typeof c === 'string' && c.trim()) return c.trim()
    return opts?.defaultModel ?? 'deepseek/deepseek-v4-flash'
  }
  return result
}

export interface SelectProviderResult {
  id: string
  keyEnv: string
}

export async function selectAgentProvider(opts?: {
  message?: string
  extraProviders?: AgentProviderDef[]
  defaultProvider?: string
}): Promise<SelectProviderResult | null> {
  const message = opts?.message ?? '选择供应商'
  const extra = opts?.extraProviders ?? []
  const allProviders = [...COMMON_PROVIDERS, ...extra]
  const customOption: AgentProviderDef = {
    id: 'custom', label: '自定义', hint: '自定义 API', keyEnv: 'CUSTOM_API_KEY', keyLabel: '自定义 API Key',
  }
  if (!allProviders.some(p => p.id === 'custom')) allProviders.push(customOption)

  const result = await select({
    message,
    options: allProviders.map(p => ({ value: p.id, label: p.label, hint: p.hint })),
  })

  if (typeof result !== 'string') return null

  if (result === 'custom') {
    const baseUrl = await input({ message: 'API base URL' })
    const keyName = await input({ message: 'API Key 环境变量名', defaultValue: 'CUSTOM_API_KEY' })
    if (typeof keyName === 'string' && keyName.trim()) {
      await promptAndSetKey(keyName.trim(), keyName.trim())
    }
    return { id: 'custom', keyEnv: typeof keyName === 'string' ? keyName.trim() : 'CUSTOM_API_KEY' }
  }

  const def = allProviders.find(p => p.id === result)
  if (def) {
    await promptAndSetKey(def.keyEnv, def.keyLabel)
    return { id: def.id, keyEnv: def.keyEnv }
  }
  return null
}

export interface McpSelectionResult {
  selected: string[]
  mcpServers: Record<string, unknown>
}

export async function selectAgentMcpServers(opts?: {
  message?: string
  preselect?: string[]
  filterOut?: string[]
}): Promise<McpSelectionResult> {
  const allMcp = getMcpServers([])
  const preselect = opts?.preselect ?? ['context7', 'brave-search', 'excalidraw']
  const filterOut = opts?.filterOut ?? []
  const message = opts?.message ?? '选择 MCP 服务器 (Space 切换, Enter 确认)'

  const mcpOptions = Object.entries(allMcp)
    .filter(([id]) => !filterOut.includes(id))
    .map(([id, def]) => ({
      value: id,
      label: def.name,
      hint: def.command,
      checked: preselect.includes(id),
    }))

  const mcpResult = await multiselect({
    message,
    options: mcpOptions,
    required: false,
  })

  const selected = Array.isArray(mcpResult)
    ? mcpResult.filter((v): v is string => typeof v === 'string')
    : []

  for (const id of selected) {
    if (id === 'brave-search') await promptAndSetKey('BRAVE_API_KEY', 'Brave API Key (留空跳过)')
    if (id === 'github') await promptAndSetKey('GITHUB_TOKEN', 'GitHub Token (留空跳过)')
    if (id === 'postgres') await promptAndSetKey('POSTGRES_DSN', 'Postgres DSN (留空跳过)')
  }

  const mcpServers: Record<string, unknown> = {}
  for (const id of selected) {
    const def = allMcp[id]
    if (!def) continue
    const entry: Record<string, unknown> = { command: def.command }
    if (def.args && def.args.length > 0) entry.args = def.args
    if (def.env) {
      const resolvedEnv: Record<string, string> = {}
      for (const [k, v] of Object.entries(def.env)) {
        if (v.startsWith('{env:')) {
          const envName = v.slice(5, -1)
          const realVal = process.env[envName]
          if (realVal) resolvedEnv[k] = realVal
        } else {
          resolvedEnv[k] = v
        }
      }
      if (Object.keys(resolvedEnv).length > 0) entry.env = resolvedEnv
    }
    mcpServers[id] = entry
  }

  return { selected, mcpServers }
}

export interface PlanModelResult {
  model: string
}

export async function selectAgentPlanModel(opts?: {
  message?: string
  defaultModel?: string
}): Promise<string> {
  const result = await select({
    message: opts?.message ?? '选择 Plan 模型',
    options: [
      { value: 'openai/gpt-5.5', label: 'OpenAI GPT-5.5', hint: '默认' },
      { value: 'openai/gpt-4o', label: 'OpenAI GPT-4o' },
      { value: 'deepseek/deepseek-v4-pro', label: 'DeepSeek V4 Pro' },
      { value: 'deepseek/deepseek-v4-flash', label: 'DeepSeek V4 Flash' },
      { value: 'openrouter/anthropic/claude-sonnet-4-20250514', label: 'Claude Sonnet 4', hint: 'via OpenRouter' },
      { value: 'custom', label: '自定义' },
      { value: 'skip', label: '不设置' },
    ],
  })

  if (typeof result !== 'string') return opts?.defaultModel ?? 'openai/gpt-5.5'
  if (result === 'custom') {
    const c = await input({ message: '输入 Plan 模型' })
    if (typeof c === 'string' && c.trim()) return c.trim()
    return opts?.defaultModel ?? 'openai/gpt-5.5'
  }
  return result
}

export async function selectAgentRelay(opts?: {
  message?: string
}): Promise<{ provider: string; baseUrl: string; keyName: string } | null> {
  const result = await select({
    message: opts?.message ?? '配置中转代理？',
    options: [
      { value: 'none', label: '直接 API (直连)', hint: '默认' },
      { value: 'openrouter', label: 'OpenRouter', hint: 'https://openrouter.ai/api/v1' },
      { value: 'aihubmix', label: 'AIHubMix', hint: 'https://aihubmix.com/v1' },
      { value: 'custom', label: '自定义中转' },
    ],
  })

  if (typeof result !== 'string' || result === 'none') return null

  if (result === 'openrouter') {
    await promptAndSetKey('OPENROUTER_API_KEY', 'OpenRouter API Key')
    return { provider: 'openrouter', baseUrl: 'https://openrouter.ai/api/v1', keyName: 'OPENROUTER_API_KEY' }
  }
  if (result === 'aihubmix') {
    await promptAndSetKey('AIHUBMIX_API_KEY', 'AIHubMix API Key')
    return { provider: 'aihubmix', baseUrl: 'https://aihubmix.com/v1', keyName: 'AIHUBMIX_API_KEY' }
  }
  if (result === 'custom') {
    const url = await input({ message: '中转 base URL' })
    const keyName = await input({ message: 'API Key 环境变量名' })
    if (typeof url === 'string' && url.trim() && typeof keyName === 'string' && keyName.trim()) {
      await promptAndSetKey(keyName.trim(), keyName.trim())
      return { provider: 'custom-relay', baseUrl: url.trim(), keyName: keyName.trim() }
    }
  }
  return null
}
