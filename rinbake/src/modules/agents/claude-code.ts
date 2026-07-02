import { $ } from 'bun'
import { hasCommand } from '../../utils'
import { logStep, logInfo, select, input, confirm, multiselect } from '../../utils/ui'
import { promptAndSetKey } from '../../config/keys'
import { getMcpServers } from '../mcp'

export const id = 'claude-code'
export const label = 'Claude Code + cc-switch'
export const description = '安装 Claude Code CLI 并配置模型、provider profiles、MCP'
export const category = 'agent' as const
export const enabled = true

export async function install(): Promise<void> {
  if (await hasCommand('claude')) {
    logStep('Claude Code 已安装')
  } else {
    logStep('安装 Claude Code...')
    await $`npm install -g @anthropic-ai/claude-code`.nothrow()
  }

  await configure()
}

export async function configure(): Promise<void> {
  const settingsPath = `${process.env.HOME || '/root'}/.claude/settings.json`
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
      { value: 'deepseek-v4-pro', label: 'DeepSeek V4 Pro' },
      { value: 'deepseek-v4-flash', label: 'DeepSeek V4 Flash', hint: '快速' },
      { value: 'openai/gpt-5.5', label: 'GPT-5.5', hint: 'via relay' },
      { value: 'openai/gpt-4o', label: 'GPT-4o', hint: 'via relay' },
      { value: 'anthropic/claude-sonnet-4-20250514', label: 'Claude Sonnet 4', hint: 'via relay' },
      { value: 'anthropic/claude-opus-4-20250514', label: 'Claude Opus 4', hint: 'via relay' },
      { value: 'claude-sonnet-4-20250514', label: 'Claude Sonnet 4', hint: '直接 Anthropic' },
      { value: 'custom', label: '自定义' },
    ],
  })

  let claudeModel = 'deepseek-v4-pro'
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
      { value: 'deepseek-v4-pro', label: 'DeepSeek V4 Pro', hint: '推荐' },
      { value: 'deepseek-v4-flash', label: 'DeepSeek V4 Flash', hint: '快速' },
      { value: 'openai/gpt-5.5', label: 'GPT-5.5', hint: 'via relay' },
      { value: 'anthropic/claude-sonnet-4-20250514', label: 'Claude Sonnet 4', hint: 'via relay' },
      { value: 'custom', label: '自定义' },
    ],
  })
  let planModel = 'deepseek-v4-pro'
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
      { value: 'bypass', label: '绕过权限检查' },
    ],
  })

  settings.model = claudeModel

  const env: Record<string, string> = (settings.env as Record<string, string>) || {}
  env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'
  env.CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK = '1'
  env.CLAUDE_CODE_ATTRIBUTION_HEADER = '0'
  env.ENABLE_TOOL_SEARCH = '1'
  env.DISABLE_EXTRA_USAGE_COMMAND = '1'
  env.ANTHROPIC_MODEL = claudeModel
  env.ANTHROPIC_DEFAULT_SONNET_MODEL = claudeModel.includes('deepseek') ? 'deepseek-v4-flash' : claudeModel
  env.ANTHROPIC_DEFAULT_HAIKU_MODEL = 'deepseek-v4-flash'
  env.CLAUDE_CODE_SUBAGENT_MODEL = claudeModel
  env.CLAUDE_CODE_MAX_OUTPUT_TOKENS = '1000000'
  env.CLAUDE_CODE_EFFORT_LEVEL = 'max'
  env.ANTHROPIC_DEFAULT_OPUS_MODEL = planModel
  settings.env = env

  settings.permissions = { defaultMode: typeof permOption === 'string' ? permOption : 'acceptEdits' }

  // Provider profiles
  const profilesDir = `${process.env.HOME || '/root'}/.config/cc-profiles`
  await $`mkdir -p ${profilesDir}`.nothrow()

  const addProfile = await confirm({ message: '添加 provider profile？', defaultValue: false })
  if (addProfile === true) {
    await addProviderProfile(profilesDir)
  }

  // cc-switch functions
  const fishFuncDir = `${process.env.HOME || '/root'}/.config/fish/functions`
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

  const home = process.env.HOME || '/root'
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

  if (Object.keys(mcpServers).length > 0) {
    (settings as Record<string, unknown>).mcpServers = mcpServers
  }

  await Bun.write(settingsPath, JSON.stringify(settings, null, 2) + '\n')
  logInfo(`Claude Code 配置已写入 ${settingsPath}`)
}

async function addProviderProfile(profilesDir: string): Promise<void> {
  const type = await select({
    message: '选择供应商类型',
    options: [
      { value: 'anthropic', label: 'Anthropic', hint: '官方 API' },
      { value: 'openrouter', label: 'OpenRouter', hint: '中转 GPT/Claude' },
      { value: 'deepseek', label: 'DeepSeek', hint: 'DeepSeek API' },
      { value: 'aihubmix', label: 'AIHubMix', hint: '中转' },
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
    case 'openrouter': {
      const key = await promptAndSetKey('OPENROUTER_API_KEY', 'OpenRouter API Key')
      if (key) content = `export ANTHROPIC_API_KEY="${key}"\nexport ANTHROPIC_BASE_URL="https://openrouter.ai/api/v1"`
      break
    }
    case 'deepseek': {
      const key = await promptAndSetKey('DEEPSEEK_API_KEY', 'DeepSeek API Key')
      if (key) content = `export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"\nexport ANTHROPIC_API_KEY="${key}"`
      break
    }
    case 'aihubmix': {
      const key = await promptAndSetKey('AIHUBMIX_API_KEY', 'AIHubMix API Key')
      if (key) content = `export ANTHROPIC_BASE_URL="https://aihubmix.com/v1"\nexport ANTHROPIC_API_KEY="${key}"`
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
