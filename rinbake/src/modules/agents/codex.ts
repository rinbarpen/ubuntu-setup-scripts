import { $ } from 'bun'
import { hasCommand, targetHome } from '../../utils'
import { logStep, logInfo, select, input, confirm, multiselect } from '../../utils/ui'
import { promptAndSetKey } from '../../config/keys'
import { readConfig, writeConfig } from '../../config/manager'
import { getMcpServers } from '../mcp'
import type { ConfigProvider } from '../../types'
import { configureClient, ensureReady } from '../omniroute'
import { getOmniRouteProvider, OMNIROUTE_DEFAULT_MODEL } from '../../config/omniroute'

export const id = 'codex'
export const label = 'Codex CLI + Multi-Provider'
export const description = '安装 codex CLI 并配置多供应商、MCP、features'
export const category = 'agent' as const
export const scope = 'user' as const
export const enabled = true

const CODEX_PACKAGE = '@openai/codex'
const CODEX_DEFAULTS = {
  // Synced from the current machine profile on 2026-09-06.
  model: 'gpt-5.6-luna',
  reasoningEffort: 'high',
  planReasoningEffort: 'high',
  approvalPolicy: 'never',
  webSearch: 'live',
  sandboxMode: 'workspace-write',
  modelInstructionsFile: './gpt-5.6-sol-unrestricted-v42.md',
  agentApprovalPolicy: 'never',
  agentPowerLevel: 'full-access',
  agentSandboxMode: 'danger-full-access',
  tuiStatusLine: [
    'model-with-reasoning', 'context-remaining', 'git-branch', 'fast-mode',
    'five-hour-limit', 'weekly-limit', 'project-name', 'run-state',
    'context-window-size',
  ],
} as const

export async function install(): Promise<void> {
  if (await hasCommand('codex')) {
    logStep('codex 已安装')
  } else {
    logStep('安装 codex CLI...')
    await $`npm install -g @openai/codex`.nothrow()
  }

  await configure()
}

export async function update(): Promise<void> {
  const result = await $`npm install -g ${CODEX_PACKAGE}@latest`.nothrow()
  if (result.exitCode !== 0) throw new Error(`npm update failed (${result.exitCode})`)
  await migrateCurrentConfig()
  logInfo('Codex CLI 已更新，配置已迁移到当前格式')
}

export async function configure(): Promise<void> {
  await ensureReady()
  await configureClient('codex')

  const cfgPath = `${targetHome()}/.codex/config.toml`
  const cfgDir = cfgPath.replace(/\/[^/]+$/, '')
  await $`mkdir -p ${cfgDir}`.nothrow()

  // Provider setup
  const providers: Record<string, ConfigProvider> = { omniroute: getOmniRouteProvider() }
  const addProviders = await confirm({ message: '添加模型供应商？', defaultValue: true })

  if (addProviders === true) {
    const providerTypes = await multiselect({
      message: '选择要添加的供应商 (Space 切换)',
      options: [
        { value: 'openai', label: 'OpenAI', hint: 'https://api.openai.com/v1' },
        { value: 'deepseek', label: 'DeepSeek', hint: 'https://api.deepseek.com' },
        { value: 'omniroute', label: 'OmniRoute', hint: 'http://localhost:20128/v1' },
      ],
      required: false,
    })

    const selectedProviders: string[] = Array.isArray(providerTypes)
      ? providerTypes.filter(v => typeof v === 'string').map(String)
      : []

    for (const pt of selectedProviders) {
      if (pt === 'omniroute') continue
      const prov: ConfigProvider = { id: pt, name: '', baseUrl: '', apiFormat: 'responses' }
      switch (pt) {
        case 'openai':
          prov.name = 'OpenAI'
          prov.baseUrl = 'https://api.openai.com/v1'
          prov.envKey = 'OPENAI_API_KEY'
          await promptAndSetKey('OPENAI_API_KEY', 'OpenAI API Key')
          break
        case 'deepseek':
          prov.name = 'DeepSeek'
          prov.baseUrl = 'https://api.deepseek.com'
          prov.envKey = 'DEEPSEEK_API_KEY'
          await promptAndSetKey('DEEPSEEK_API_KEY', 'DeepSeek API Key')
          break
      }
      providers[pt] = prov
    }
  }

  let defaultProvider = Object.keys(providers)[0] || ''
  let defaultModel: string = OMNIROUTE_DEFAULT_MODEL
  if (Object.keys(providers).length > 0) {
    const providerKeys = Object.keys(providers)
    const dp = await select({
      message: '选择默认供应商',
      options: providerKeys.map(pk => ({ value: pk, label: providers[pk].name })),
    })
    if (typeof dp === 'string') {
      defaultProvider = dp
      const modelInput = await input({ message: `模型 ID (${providers[dp].name})`, defaultValue: OMNIROUTE_DEFAULT_MODEL })
      if (typeof modelInput === 'string' && modelInput.trim()) defaultModel = modelInput.trim()
    }
  }

  const planOption = await select({
    message: '选择 Plan 模式 reasoning effort',
    options: [
      { value: 'high', label: 'high' },
      { value: 'xhigh', label: 'xhigh' },
      { value: 'medium', label: 'medium' },
      { value: 'skip', label: '不设置' },
    ],
  })

  // Features
  const features = await multiselect({
    message: '选择开启的 features (Space 切换)',
      options: [
        { value: 'hooks', label: '生命周期钩子', hint: 'lifecycle hooks', checked: true },
        { value: 'multi_agent', label: '多 Agent', checked: true },
        { value: 'goals', label: 'Goals / 自动续接', checked: true },
        { value: 'shell_tool', label: 'Shell 工具', checked: true },
        { value: 'unified_exec', label: '统一 PTY 执行', checked: true },
        { value: 'personality', label: '人格选择', checked: true },
        { value: 'guardian_approval', label: 'Guardian 审批', checked: true },
        { value: 'prevent_idle_sleep', label: '防止空闲休眠', checked: true },
        { value: 'memories', label: '记忆系统', checked: false },
        { value: 'apps', label: 'ChatGPT Apps', checked: false },
        { value: 'network_proxy', label: '沙箱网络代理', hint: '实验性', checked: false },
    ],
    required: false,
  })
  const selectedFeatures: string[] = Array.isArray(features)
    ? features.filter(v => typeof v === 'string').map(String)
    : ['hooks', 'multi_agent', 'goals', 'shell_tool', 'unified_exec', 'personality', 'guardian_approval', 'prevent_idle_sleep']

  // Approval
  const approval = await select({
    message: '选择默认批准策略',
    options: [
      { value: 'never', label: '从不询问' },
      { value: 'untrusted', label: '仅不受信命令询问' },
      { value: 'on-request', label: '按需批准' },
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
      checked: ['context7', 'chrome-devtools'].includes(id),
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
  const fishFuncDir = `${targetHome()}/.config/fish/functions`
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
        case "omniroute"
            read -s -P "Enter OMNIROUTE_API_KEY (optional): " key
            set -gx OMNIROUTE_API_KEY $key
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
    approvalPolicy: typeof approval === 'string' ? approval : CODEX_DEFAULTS.approvalPolicy,
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
    `model_reasoning_effort = "${CODEX_DEFAULTS.reasoningEffort}"`,
    `model_reasoning_summary = "auto"`,
    `model_verbosity = "medium"`,
    `personality = "pragmatic"`,
    `plan_mode_reasoning_effort = ${JSON.stringify(params.planModel || CODEX_DEFAULTS.planReasoningEffort)}`,
    `approval_policy = ${JSON.stringify(params.approvalPolicy)}`,
    `sandbox_mode = ${JSON.stringify(CODEX_DEFAULTS.sandboxMode)}`,
    `web_search = "${CODEX_DEFAULTS.webSearch}"`,
    `model_instructions_file = ${JSON.stringify(CODEX_DEFAULTS.modelInstructionsFile)}`,
  ]

  if (params.defaultModel) lines.push(`model = ${JSON.stringify(params.defaultModel)}`)
  if (params.defaultProvider) lines.push(`model_provider = ${JSON.stringify(params.defaultProvider)}`)

  lines.push('')
  lines.push('[features]')
  const allFeatures = [
    'apps', 'goals', 'guardian_approval', 'hooks', 'memories', 'multi_agent',
    'network_proxy', 'personality', 'prevent_idle_sleep', 'shell_tool', 'unified_exec',
  ]
  for (const feat of allFeatures) {
    lines.push(`${feat} = ${params.features.includes(feat) ? 'true' : 'false'}`)
  }

  lines.push('')
  lines.push('[tui]')
  lines.push(`status_line = ${JSON.stringify(CODEX_DEFAULTS.tuiStatusLine)}`)

  lines.push('')
  lines.push('[agent]')
  lines.push(`approval_policy = ${JSON.stringify(CODEX_DEFAULTS.agentApprovalPolicy)}`)
  lines.push(`power_level = ${JSON.stringify(CODEX_DEFAULTS.agentPowerLevel)}`)
  lines.push(`sandbox_mode = ${JSON.stringify(CODEX_DEFAULTS.agentSandboxMode)}`)

  const providerEntries = Object.entries(params.providers)
  if (providerEntries.length > 0) {
    lines.push('')
    lines.push('# Model providers')
  }
  for (const [id, prov] of providerEntries) {
    // OpenAI is a built-in provider and cannot be overridden in model_providers.
    if (id === 'openai') continue
    lines.push('')
    lines.push(`[model_providers.${id}]`)
    lines.push(`name = ${JSON.stringify(prov.name)}`)
    lines.push(`base_url = ${JSON.stringify(prov.baseUrl)}`)
    if (prov.envKey) lines.push(`env_key = ${JSON.stringify(prov.envKey)}`)
    if (prov.apiFormat) lines.push(`wire_api = ${JSON.stringify(prov.apiFormat === 'chat' ? 'responses' : prov.apiFormat)}`)
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
      const staticEnv: Record<string, string> = {}
      const envVars: string[] = []
      for (const [k, v] of Object.entries(env)) {
        if (v.startsWith('{env:')) {
          const envName = v.slice(5, -1)
          envVars.push(envName)
        } else {
          staticEnv[k] = v
        }
      }
      if (envVars.length > 0) {
        lines.push(`env_vars = [${envVars.map(v => JSON.stringify(v)).join(', ')}]`)
      }
      if (Object.keys(staticEnv).length > 0) {
        lines.push(`[mcp_servers.${JSON.stringify(id)}.env]`)
        for (const [k, v] of Object.entries(staticEnv)) lines.push(`${k} = ${JSON.stringify(v)}`)
      }
    }
  }

  return lines.join('\n') + '\n'
}

/** Migrate an existing config while retaining user-defined settings. */
export async function migrateCurrentConfig(): Promise<void> {
  const cfgPath = `${targetHome()}/.codex/config.toml`
  const cfgDir = cfgPath.replace(/\/[^/]+$/, '')
  await $`mkdir -p ${cfgDir}`.nothrow()
  const file = Bun.file(cfgPath)
  const old = (await file.exists()) ? await file.text() : ''
  const lines = old.split(/\r?\n/)
  const managed: Record<string, string> = {
    model: OMNIROUTE_DEFAULT_MODEL,
    model_reasoning_effort: CODEX_DEFAULTS.reasoningEffort,
    model_reasoning_summary: 'auto',
    model_verbosity: 'medium',
    personality: 'pragmatic',
    plan_mode_reasoning_effort: CODEX_DEFAULTS.planReasoningEffort,
    approval_policy: CODEX_DEFAULTS.approvalPolicy,
    sandbox_mode: 'workspace-write',
    web_search: CODEX_DEFAULTS.webSearch,
  }
  const output = lines
    .filter(line => !/^\s*plan_model\s*=/.test(line))
    .map(line => line.replace(
      /^(\s*wire_api\s*=\s*)"chat"\s*$/,
      '$1"responses"',
    ))
  const firstTable = output.findIndex(line => /^\s*\[/.test(line))
  const topLevelEnd = firstTable >= 0 ? firstTable : output.length
  let insertAt = topLevelEnd
  for (const [key, value] of Object.entries(managed)) {
    const pattern = new RegExp(`^\\s*${key}\\s*=`)
    const index = output.slice(0, topLevelEnd).findIndex(line => pattern.test(line))
    const line = `${key} = ${JSON.stringify(value)}`
    if (index >= 0) output[index] = line
    else output.splice(insertAt++, 0, line)
  }
  await Bun.write(cfgPath, output.join('\n').replace(/\n+$/, '') + '\n')
}

export async function detect(): Promise<boolean> {
  return hasCommand('codex')
}
