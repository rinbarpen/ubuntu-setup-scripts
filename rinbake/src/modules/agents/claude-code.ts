import { $ } from 'bun'
import { hasCommand, targetHome } from '../../utils'
import { logStep, logInfo, select, input, confirm, multiselect } from '../../utils/ui'
import { promptAndSetKey } from '../../config/keys'
import { getMcpServers } from '../mcp'
import { configureClient, ensureReady } from '../omniroute'
import { getOmniRouteClientUrl, OMNIROUTE_DEFAULT_MODEL } from '../../config/omniroute'

export const id = 'claude-code'
export const label = 'Claude Code + cc-switch'
export const description = '安装 Claude Code CLI 并通过 OmniRoute 配置模型、profiles、MCP'
export const category = 'agent' as const
export const scope = 'user' as const
export const enabled = true

const CLAUDE_PACKAGE = '@anthropic-ai/claude-code'
const CLAUDE_DEFAULTS = {
  // Synced from the current machine profile on 2026-09-06.
  model: 'haiku',
  subagentModel: 'deepseek-v4-flash',
  effort: 'max',
  persistedEffort: 'xhigh',
  permissionMode: 'bypassPermissions',
  baseUrl: getOmniRouteClientUrl('claude-code'),
  modelId: OMNIROUTE_DEFAULT_MODEL,
  sonnetModel: OMNIROUTE_DEFAULT_MODEL,
  haikuModel: OMNIROUTE_DEFAULT_MODEL,
  statusLineCommand: 'bash ~/.claude/statusline-command.sh',
} as const

export async function install(): Promise<void> {
  if (await hasCommand('claude')) {
    logStep('Claude Code 已安装')
  } else {
    logStep('安装 Claude Code...')
    await $`npm install -g @anthropic-ai/claude-code`.nothrow()
  }

  await configure()
}

export async function update(): Promise<void> {
  let result = await $`claude update`.nothrow()
  if (result.exitCode !== 0) {
    result = await $`npm install -g ${CLAUDE_PACKAGE}@latest`.nothrow()
  }
  if (result.exitCode !== 0) throw new Error(`Claude Code update failed (${result.exitCode})`)
  await migrateCurrentSettings()
  logInfo('Claude Code 已更新，配置已迁移到当前格式')
}

export async function configure(): Promise<void> {
  await ensureReady()
  await configureClient('claude-code')

  const settingsPath = `${targetHome()}/.claude/settings.json`
  const settingsDir = settingsPath.replace(/\/[^/]+$/, '')
  await $`mkdir -p ${settingsDir}`.nothrow()

  let settings: Record<string, unknown> = {}
  try {
    const f = Bun.file(settingsPath)
    if (await f.exists()) settings = JSON.parse(await f.text())
  } catch {}

  const modelOption = await select({
    message: '选择默认模型',
    options: [
      { value: 'haiku', label: 'haiku', hint: '快速任务' },
      { value: 'opusplan', label: 'opusplan', hint: 'Plan 用 Opus，执行用 Sonnet' },
      { value: 'opus', label: 'opus', hint: '复杂推理' },
      { value: 'sonnet', label: 'sonnet', hint: '日常编码' },
      { value: 'claude-opus-5', label: 'Claude Opus 5', hint: '固定版本' },
      { value: 'claude-sonnet-5', label: 'Claude Sonnet 5', hint: '固定版本' },
      { value: 'custom', label: '自定义' },
    ],
  })

  let claudeModel: string = CLAUDE_DEFAULTS.model
  if (typeof modelOption === 'string') {
    if (modelOption === 'custom') {
      const c = await input({ message: '输入模型 ID' })
      if (typeof c === 'string' && c.trim()) claudeModel = c.trim()
    } else {
      claudeModel = modelOption
    }
  }

  const planOption = await select({
    message: '选择 Plan 模式模型',
    options: [
      { value: 'opus', label: 'opus', hint: '当前 Opus' },
      { value: 'sonnet', label: 'sonnet', hint: '当前 Sonnet' },
      { value: 'claude-opus-5', label: 'Claude Opus 5' },
      { value: 'claude-sonnet-5', label: 'Claude Sonnet 5' },
      { value: 'custom', label: '自定义' },
    ],
  })
  let planModel = 'opus'
  if (typeof planOption === 'string') {
    if (planOption === 'custom') {
      const c = await input({ message: '输入 Plan 模型 ID' })
      if (typeof c === 'string' && c.trim()) planModel = c.trim()
    } else {
      planModel = planOption
    }
  }

  const permOption = await select({
    message: '选择默认权限模式',
    options: [
      { value: 'acceptEdits', label: '自动接受编辑', hint: '推荐' },
      { value: 'default', label: '每次询问' },
      { value: 'plan', label: 'Plan 模式' },
      { value: 'dontAsk', label: '不询问（按规则执行）' },
      { value: 'bypassPermissions', label: '绕过权限检查' },
    ],
  })

  settings['$schema'] = 'https://json.schemastore.org/claude-code-settings.json'
  settings.model = claudeModel
  settings.effortLevel = CLAUDE_DEFAULTS.persistedEffort
  settings.skipDangerousModePermissionPrompt = true
  settings.statusLine = { type: 'command', command: CLAUDE_DEFAULTS.statusLineCommand }

  const env: Record<string, string> = (settings.env as Record<string, string>) || {}
  env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'
  env.CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK = '1'
  env.CLAUDE_CODE_ATTRIBUTION_HEADER = '0'
  env.ENABLE_TOOL_SEARCH = '1'
  env.DISABLE_EXTRA_USAGE_COMMAND = '1'
  env.ANTHROPIC_BASE_URL = CLAUDE_DEFAULTS.baseUrl
  env.ANTHROPIC_MODEL = env.ANTHROPIC_MODEL || (claudeModel === 'haiku' ? CLAUDE_DEFAULTS.modelId : claudeModel)
  env.ANTHROPIC_DEFAULT_OPUS_MODEL = env.ANTHROPIC_DEFAULT_OPUS_MODEL || CLAUDE_DEFAULTS.modelId
  env.ANTHROPIC_DEFAULT_SONNET_MODEL = env.ANTHROPIC_DEFAULT_SONNET_MODEL || CLAUDE_DEFAULTS.sonnetModel
  env.ANTHROPIC_DEFAULT_HAIKU_MODEL = env.ANTHROPIC_DEFAULT_HAIKU_MODEL || CLAUDE_DEFAULTS.haikuModel
  env.CLAUDE_CODE_SUBAGENT_MODEL = CLAUDE_DEFAULTS.subagentModel
  env.CLAUDE_CODE_MAX_OUTPUT_TOKENS = '1000000'
  env.CLAUDE_CODE_EFFORT_LEVEL = CLAUDE_DEFAULTS.effort
  if (typeof planModel === 'string' && planModel.trim()) {
    env.ANTHROPIC_DEFAULT_OPUS_MODEL = planModel === 'opus'
      ? 'claude-opus-5'
      : planModel === 'sonnet' ? 'claude-sonnet-5' : planModel
  }
  settings.env = env

  const permissions = (settings.permissions as Record<string, unknown>) || {}
  permissions.defaultMode = typeof permOption === 'string' ? permOption : CLAUDE_DEFAULTS.permissionMode
  settings.permissions = permissions

  // Provider profiles
  const profilesDir = `${targetHome()}/.config/cc-profiles`
  await $`mkdir -p ${profilesDir}`.nothrow()

  const addProfile = await confirm({ message: '添加 provider profile？', defaultValue: false })
  if (addProfile === true) {
    await addProviderProfile(profilesDir)
  }

  // cc-switch functions
  const fishFuncDir = `${targetHome()}/.config/fish/functions`
  await $`mkdir -p ${fishFuncDir}`.nothrow()

  await Bun.write(
    `${fishFuncDir}/cc_switch.fish`,
    `function cc_switch
    if test -z "$argv[1]"
        echo "Usage: cc_switch <profile>"
        echo "Available profiles:"
        ls ~/.config/cc-profiles/*.env 2>/dev/null | xargs -I{} basename {} .env
        return 1
    end
    set profile_file ~/.config/cc-profiles/$argv[1].env
    if not test -f $profile_file
        echo "Profile not found: $argv[1]"
        return 1
    end
    bass source $profile_file
    echo "Switched to profile: $argv[1]"
end\n`
  )

  const home = targetHome()
  const bashrcPath = `${home}/.bashrc`
  const bashrcMarker = '# rinbake: cc-switch'
  const bashrcText = (await Bun.file(bashrcPath).exists()) ? await Bun.file(bashrcPath).text() : ''
  if (!bashrcText.includes(bashrcMarker)) {
    await Bun.write(bashrcPath, bashrcText + `
${bashrcMarker}
cc-switch() {
  local profile="\${1:-}"
  if [[ -z "$profile" ]]; then
    echo "Usage: cc-switch <profile>"
    ls ~/.config/cc-profiles/*.env 2>/dev/null | xargs -I{} basename {} .env
    return 1
  fi
  local f="$HOME/.config/cc-profiles/\${profile}.env"
  if [[ ! -f "$f" ]]; then
    echo "Profile not found: $profile"
    return 1
  fi
  source "$f"
  echo "Switched to profile: $profile"
}
`)
  }

  // MCP servers
  await promptAndSetKey('BRAVE_API_KEY', 'Brave API Key (留空跳过)')

  const mcpAll = getMcpServers([])
  const mcpOptions = Object.entries(mcpAll).filter(([id]) => !['postgres', 'github'].includes(id)).map(([id, def]) => ({
    value: id,
    label: def.name,
    hint: def.command,
    checked: ['context7', 'brave-search', 'excalidraw', 'puppeteer'].includes(id),
  }))

  const mcpResult = await multiselect({
    message: '选择 Claude Code MCP 服务器（Space 切换, Enter 确认）',
    options: mcpOptions,
  })

  const selectedMcp = Array.isArray(mcpResult)
    ? mcpResult.filter((v): v is string => typeof v === 'string')
    : []

  const mcpServers: Record<string, unknown> = {}
  for (const id of selectedMcp) {
    const def = mcpAll[id]
    if (!def) continue
    const entry: Record<string, unknown> = {
      type: 'stdio',
      command: def.command,
      args: def.args || [],
    }
    if (def.env) {
      const filteredEnv: Record<string, string> = {}
      for (const [k, v] of Object.entries(def.env)) {
        if (v.startsWith('{env:')) {
          const envName = v.slice(5, -1)
          const realVal = process.env[envName]
          if (realVal) filteredEnv[k] = realVal
        } else {
          filteredEnv[k] = v
        }
      }
      if (Object.keys(filteredEnv).length > 0) entry.env = filteredEnv
    }
    mcpServers[id] = entry
  }

  const legacyMcp = (settings as Record<string, unknown>).mcpServers
  delete (settings as Record<string, unknown>).mcpServers
  const mcpToWrite = Object.keys(mcpServers).length > 0 ? mcpServers : legacyMcp
  if (mcpToWrite && typeof mcpToWrite === 'object') await mergeClaudeMcpConfig(mcpToWrite as Record<string, unknown>)

  await Bun.write(settingsPath, JSON.stringify(settings, null, 2) + '\n')
  logInfo(`Claude Code 配置已写入 ${settingsPath}`)
}

async function addProviderProfile(profilesDir: string): Promise<void> {
  const type = await select({
    message: '选择供应商类型',
    options: [
      { value: 'anthropic', label: 'Anthropic', hint: '官方 API' },
      { value: 'deepseek', label: 'DeepSeek', hint: 'DeepSeek API' },
      { value: 'custom', label: '自定义' },
    ],
  })

  if (typeof type !== 'string') return

  let content = ''
  switch (type) {
    case 'anthropic': {
      const key = await promptAndSetKey('ANTHROPIC_API_KEY', 'Anthropic API Key')
      if (key) content = `export ANTHROPIC_API_KEY="${key}"`
      break
    }
    case 'deepseek': {
      const key = await promptAndSetKey('DEEPSEEK_API_KEY', 'DeepSeek API Key')
      if (key) content = `export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"\nexport ANTHROPIC_API_KEY="${key}"`
      break
    }
    case 'custom': {
      const baseUrl = await input({ message: 'API base URL' })
      const key = await promptAndSetKey('CUSTOM_API_KEY', 'Custom API Key')
      if (typeof baseUrl === 'string' && key) {
        content = `export ANTHROPIC_API_KEY="${key}"\nexport ANTHROPIC_BASE_URL="${baseUrl}"`
      }
      break
    }
  }

  if (content) {
    await Bun.write(`${profilesDir}/${type}.env`, content + '\n')
    logInfo(`Profile saved: ${profilesDir}/${type}.env`)
  }
}

export async function detect(): Promise<boolean> {
  return hasCommand('claude')
}

export async function migrateCurrentSettings(): Promise<void> {
  const settingsPath = `${targetHome()}/.claude/settings.json`
  const settingsDir = settingsPath.replace(/\/[^/]+$/, '')
  await $`mkdir -p ${settingsDir}`.nothrow()
  let settings: Record<string, unknown> = {}
  const file = Bun.file(settingsPath)
  try {
    if (await file.exists()) settings = JSON.parse(await file.text())
  } catch {
    settings = {}
  }
  settings['$schema'] = 'https://json.schemastore.org/claude-code-settings.json'
  const legacyMcp = settings.mcpServers
  delete settings.mcpServers
  const currentModel = typeof settings.model === 'string' && settings.model.trim()
    ? settings.model
    : CLAUDE_DEFAULTS.model
  settings.model = currentModel
  settings.effortLevel = CLAUDE_DEFAULTS.persistedEffort
  settings.skipDangerousModePermissionPrompt = settings.skipDangerousModePermissionPrompt ?? true
  settings.statusLine = settings.statusLine || { type: 'command', command: CLAUDE_DEFAULTS.statusLineCommand }
  const env = (settings.env as Record<string, string>) || {}
  env.ANTHROPIC_BASE_URL = CLAUDE_DEFAULTS.baseUrl
  env.ANTHROPIC_MODEL = currentModel === 'haiku' ? CLAUDE_DEFAULTS.modelId : currentModel
  env.ANTHROPIC_DEFAULT_OPUS_MODEL = CLAUDE_DEFAULTS.modelId
  env.CLAUDE_CODE_SUBAGENT_MODEL = CLAUDE_DEFAULTS.subagentModel
  env.CLAUDE_CODE_MAX_OUTPUT_TOKENS = env.CLAUDE_CODE_MAX_OUTPUT_TOKENS || '1000000'
  env.CLAUDE_CODE_EFFORT_LEVEL = CLAUDE_DEFAULTS.effort
  env.ANTHROPIC_DEFAULT_SONNET_MODEL = CLAUDE_DEFAULTS.sonnetModel
  env.ANTHROPIC_DEFAULT_HAIKU_MODEL = env.ANTHROPIC_DEFAULT_HAIKU_MODEL || CLAUDE_DEFAULTS.haikuModel
  settings.env = env
  const permissions = (settings.permissions as Record<string, unknown>) || {}
  if (permissions.defaultMode === 'bypass') permissions.defaultMode = 'bypassPermissions'
  if (!permissions.defaultMode) permissions.defaultMode = CLAUDE_DEFAULTS.permissionMode
  settings.permissions = permissions
  await Bun.write(settingsPath, JSON.stringify(settings, null, 2) + '\n')
  if (legacyMcp && typeof legacyMcp === 'object') await mergeClaudeMcpConfig(legacyMcp as Record<string, unknown>)
}

/** User-scoped MCP servers live in ~/.claude.json in current Claude Code. */
async function mergeClaudeMcpConfig(mcpServers: Record<string, unknown>): Promise<void> {
  const path = `${targetHome()}/.claude.json`
  let config: Record<string, unknown> = {}
  const file = Bun.file(path)
  try {
    if (await file.exists()) config = JSON.parse(await file.text())
  } catch {
    config = {}
  }
  config.mcpServers = { ...(config.mcpServers as Record<string, unknown> || {}), ...mcpServers }
  await Bun.write(path, JSON.stringify(config, null, 2) + '\n')
}
