import { $ } from 'bun'
import { hasCommand } from '../../utils'
import { logStep, logInfo, select, input, confirm, multiselect } from '../../utils/ui'
import { promptAndSetKey } from '../../config/keys'
import { readConfig, writeConfig } from '../../config/manager'
import { getMcpServers } from '../mcp'
import type { ConfigProvider } from '../../types'

export const id = 'codex'
export const label = 'Codex CLI + Multi-Provider'
export const description = '安装 codex CLI 并配置多供应商、MCP、features'
export const category = 'agent' as const
export const enabled = true

export async function install(): Promise<void> {
  if (await hasCommand('codex')) {
    logStep('codex 已安装')
  } else {
    logStep('安装 codex CLI...')
    await $`npm install -g @openai/codex`.nothrow()
  }

  await configure()
}

export async function configure(): Promise<void> {
  const cfgPath = `${process.env.HOME || '/root'}/.codex/config.toml`
  const cfgDir = cfgPath.replace(/\/[^/]+$/, '')
  await $`mkdir -p ${cfgDir}`.nothrow()

  // Provider setup
  const providers: Record<string, ConfigProvider> = {}
  const addProviders = await confirm({ message: '添加模型供应商？', defaultValue: true })

  if (addProviders === true) {
    const providerTypes = await multiselect({
      message: '选择要添加的供应商 (Space 切换)',
      options: [
        { value: 'openai', label: 'OpenAI', hint: 'https://api.openai.com/v1' },
        { value: 'deepseek', label: 'DeepSeek', hint: 'https://api.deepseek.com' },
        { value: 'openrouter', label: 'OpenRouter', hint: '中转 GPT/Claude' },
        { value: 'aihubmix', label: 'AIHubMix', hint: '中转' },
      ],
      required: false,
    })

    const selectedProviders = Array.isArray(providerTypes)
      ? providerTypes.filter((v): v is string => typeof v === 'string')
      : []

    for (const pt of selectedProviders) {
      const prov: ConfigProvider = { id: pt, name: '', baseUrl: '', apiFormat: 'chat' }
      switch (pt) {
        case 'openai':
          prov.name = 'OpenAI'
          prov.baseUrl = 'https://api.openai.com/v1'
          prov.envKey = 'OPENAI_API_KEY'
          prov.apiFormat = 'responses'
          await promptAndSetKey('OPENAI_API_KEY', 'OpenAI API Key')
          break
        case 'deepseek':
          prov.name = 'DeepSeek'
          prov.baseUrl = 'https://api.deepseek.com'
          prov.envKey = 'DEEPSEEK_API_KEY'
          await promptAndSetKey('DEEPSEEK_API_KEY', 'DeepSeek API Key')
          break
        case 'openrouter':
          prov.name = 'OpenRouter'
          prov.baseUrl = 'https://openrouter.ai/api/v1'
          prov.envKey = 'OPENROUTER_API_KEY'
          await promptAndSetKey('OPENROUTER_API_KEY', 'OpenRouter API Key')
          break
        case 'aihubmix':
          prov.name = 'AIHubMix'
          prov.baseUrl = 'https://aihubmix.com/v1'
          prov.envKey = 'AIHUBMIX_API_KEY'
          await promptAndSetKey('AIHUBMIX_API_KEY', 'AIHubMix API Key')
          break
      }
      providers[pt] = prov
    }
  }

  let defaultProvider = Object.keys(providers)[0] || ''
  let defaultModel = 'gpt-5'
  if (Object.keys(providers).length > 0) {
    const providerKeys = Object.keys(providers)
    const dp = await select({
      message: '选择默认供应商',
      options: providerKeys.map(pk => ({ value: pk, label: providers[pk].name })),
    })
    if (typeof dp === 'string') {
      defaultProvider = dp
      const modelInput = await input({ message: `模型 ID (${providers[dp].name})`, defaultValue: 'gpt-5' })
      if (typeof modelInput === 'string' && modelInput.trim()) defaultModel = modelInput.trim()
    }
  }

  const planOption = await select({
    message: '选择 Plan 模型',
    options: [
      { value: 'deepseek-v4-pro', label: 'DeepSeek V4 Pro', hint: '推荐' },
      { value: 'deepseek-v4-flash', label: 'DeepSeek V4 Flash' },
      { value: 'gpt-5.5', label: 'GPT-5.5', hint: 'via relay' },
      { value: 'custom', label: '自定义' },
      { value: 'skip', label: '不设置' },
    ],
  })

  // Features
  const features = await multiselect({
    message: '选择开启的 features (Space 切换)',
    options: [
      { value: 'hooks', label: '生命周期钩子', hint: 'lifecycle hooks', checked: true },
      { value: 'memories', label: '记忆系统', checked: false },
      { value: 'undo', label: '撤销支持', checked: false },
      { value: 'apps', label: 'ChatGPT Apps', hint: '实验性', checked: false },
      { value: 'network_proxy', label: '沙箱网络代理', hint: '实验性', checked: false },
    ],
    required: false,
  })
  const selectedFeatures = Array.isArray(features)
    ? features.filter((v): v is string => typeof v === 'string')
    : ['hooks']

  // Approval
  const approval = await select({
    message: '选择默认批准策略',
    options: [
      { value: 'on-request', label: '按需批准', hint: '推荐' },
      { value: 'never', label: '从不询问', hint: 'bypass 等效' },
      { value: 'always', label: '始终询问' },
    ],
  })

  // MCP
  const allMcp = getMcpServers([])
  const mcpResult = await multiselect({
    message: '选择 MCP 服务器（Space 切换）',
    options: Object.entries(allMcp).map(([id, def]) => ({
      value: id,
      label: def.name,
      hint: def.command,
      checked: ['context7', 'brave-search', 'excalidraw'].includes(id),
    })),
    required: false,
  })
  const selectedMcp = Array.isArray(mcpResult)
    ? mcpResult.filter((v): v is string => typeof v === 'string')
    : []

  for (const id of selectedMcp) {
    if (id === 'brave-search') await promptAndSetKey('BRAVE_API_KEY', 'Brave API Key (留空跳过)')
    if (id === 'github') await promptAndSetKey('GITHUB_TOKEN', 'GitHub Token (留空跳过)')
    if (id === 'postgres') await promptAndSetKey('POSTGRES_DSN', 'Postgres DSN (留空跳过)')
  }

  // codex-auth functions
  const fishFuncDir = `${process.env.HOME || '/root'}/.config/fish/functions`
  await $`mkdir -p ${fishFuncDir}`.nothrow()

  await Bun.write(
    `${fishFuncDir}/codex_auth.fish`,
    `function codex_auth
    set -l cfg "$HOME/.codex/config.toml"
    set -l provider "openai"
    if test -f "$cfg"
        set provider (grep -m1 '^model_provider' "$cfg" | sed 's/.*= *"\\(.*\\)"/\\1/' 2>/dev/null; or echo "openai")
    end
    switch "$provider"
        case "openrouter"
            read -s -P "Enter OPENROUTER_API_KEY: " key
            set -gx OPENROUTER_API_KEY $key
        case "aihubmix"
            read -s -P "Enter AIHUBMIX_API_KEY: " key
            set -gx AIHUBMIX_API_KEY $key
        case "deepseek"
            read -s -P "Enter DEEPSEEK_API_KEY: " key
            set -gx DEEPSEEK_API_KEY $key
        case '*'
            read -s -P "Enter OPENAI_API_KEY: " key
            set -gx OPENAI_API_KEY $key
    end
    echo "API key set for this session"
end\n`
  )

  // Generate TOML config
  const tomlContent = generateToml({
    defaultProvider,
    defaultModel,
    planModel: typeof planOption === 'string' && planOption !== 'skip' ? planOption : '',
    approvalPolicy: typeof approval === 'string' ? approval : 'on-request',
    features: selectedFeatures,
    providers,
    mcpServers: selectedMcp,
    allMcp,
  })

  await Bun.write(cfgPath, tomlContent)
  logInfo(`codex 配置已写入 ${cfgPath}`)
}

interface TomlParams {
  defaultProvider: string
  defaultModel: string
  planModel: string
  approvalPolicy: string
  features: string[]
  providers: Record<string, ConfigProvider>
  mcpServers: string[]
  allMcp: ReturnType<typeof getMcpServers>
}

function generateToml(params: TomlParams): string {
  const lines: string[] = [
    '# Codex configuration — generated by rinbake',
    '',
    `model_reasoning_effort = "medium"`,
    `plan_mode_reasoning_effort = "xhigh"`,
    `approval_policy = ${JSON.stringify(params.approvalPolicy)}`,
    `sandbox_mode = "workspace-write"`,
  ]

  if (params.defaultModel) lines.push(`model = ${JSON.stringify(params.defaultModel)}`)
  if (params.planModel) lines.push(`plan_model = ${JSON.stringify(params.planModel)}`)
  if (params.defaultProvider) lines.push(`model_provider = ${JSON.stringify(params.defaultProvider)}`)

  lines.push('')
  lines.push('[features]')
  const allFeatures = ['memories', 'hooks', 'undo', 'apps', 'network_proxy']
  for (const feat of allFeatures) {
    lines.push(`${feat} = ${params.features.includes(feat) ? 'true' : 'false'}`)
  }

  const providerEntries = Object.entries(params.providers)
  if (providerEntries.length > 0) {
    lines.push('')
    lines.push('# Model providers')
  }
  for (const [id, prov] of providerEntries) {
    lines.push('')
    lines.push(`[model_providers.${id}]`)
    lines.push(`name = ${JSON.stringify(prov.name)}`)
    lines.push(`base_url = ${JSON.stringify(prov.baseUrl)}`)
    if (prov.envKey) lines.push(`env_key = ${JSON.stringify(prov.envKey)}`)
    if (prov.apiFormat) lines.push(`wire_api = ${JSON.stringify(prov.apiFormat)}`)
  }

  if (params.mcpServers.length > 0) {
    lines.push('')
    lines.push('# MCP servers')
  }
  for (const id of params.mcpServers) {
    const def = params.allMcp[id]
    if (!def) continue
    lines.push('')
    lines.push(`[mcp_servers.${JSON.stringify(id)}]`)
    lines.push(`command = ${JSON.stringify(def.command)}`)
    if (def.args && def.args.length > 0) {
      lines.push(`args = [${def.args.map(a => JSON.stringify(a)).join(', ')}]`)
    }
    if (def.env && Object.keys(def.env).length > 0) {
      const env = def.env as Record<string, string>
      lines.push(`[mcp_servers.${JSON.stringify(id)}.env]`)
      for (const [k, v] of Object.entries(env)) {
        if (v.startsWith('{env:')) {
          const envName = v.slice(5, -1)
          const realVal = process.env[envName] || ''
          if (realVal) lines.push(`${k} = ${JSON.stringify(realVal)}`)
        } else {
          lines.push(`${k} = ${JSON.stringify(v)}`)
        }
      }
    }
  }

  return lines.join('\n') + '\n'
}

export async function detect(): Promise<boolean> {
  return hasCommand('codex')
}
