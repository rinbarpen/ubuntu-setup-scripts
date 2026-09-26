import { $ } from 'bun'
import * as fs from 'node:fs'
import color from 'picocolors'
import { intro, outro, select, input, logInfo, logWarn, logError, isCancelled } from '../utils/ui'
import { ensureReady } from '../modules/omniroute'
import { getOmniRouteClientUrl, OMNIROUTE_API_KEY, OMNIROUTE_DEFAULT_MODEL } from '../config/omniroute'
import { targetHome } from '../utils'

const CLAUDE_SETTINGS = `${targetHome()}/.claude/settings.json`
const BACKUP_DIR = `${targetHome()}/.claude/backups`

interface ProviderDef {
  url: string
  models: string[]
  key: string
}

const PROVIDERS: Record<string, ProviderDef> = {
  deepseek:   { url: 'https://api.deepseek.com/anthropic',              models: ['deepseek-v4-pro', 'deepseek-v4-flash'],                 key: 'ANTHROPIC_AUTH_TOKEN' },
  qwen:       { url: 'https://dashscope-intl.aliyuncs.com/apps/anthropic', models: ['qwen3.6-plus', 'qwen3-max', 'qwen3-coder-plus'],   key: 'ANTHROPIC_AUTH_TOKEN' },
  glm:        { url: 'https://open.bigmodel.cn/api/anthropic',          models: ['glm-5', 'glm-4.7'],                                   key: 'ANTHROPIC_AUTH_TOKEN' },
  minimax:    { url: 'https://api.minimaxi.com/anthropic',              models: ['MiniMax-M2.7', 'MiniMax-M2.5'],                       key: 'ANTHROPIC_AUTH_TOKEN' },
  aixor:      { url: 'https://aixor.org',                               models: ['deepseek-v4-pro', 'qwen3.6-plus', 'glm-5', 'gpt-4o'], key: 'ANTHROPIC_AUTH_TOKEN' },
  omniroute:  { url: getOmniRouteClientUrl('claude-code'),              models: [OMNIROUTE_DEFAULT_MODEL, 'auto/coding', 'auto/fast'], key: OMNIROUTE_API_KEY },
}

function printHeader(): void {
  console.log(color.bold('========================================'))
  console.log(color.bold('  Claude Code 模型切换工具'))
  console.log(color.bold('========================================'))
}

function getCurrentProvider(): string {
  try {
    if (!fs.existsSync(CLAUDE_SETTINGS)) return 'unknown'
    const content = fs.readFileSync(CLAUDE_SETTINGS, 'utf-8')
    const m = content.match(/"ANTHROPIC_BASE_URL":\s*"([^"]+)"/)
    if (!m) return 'unknown'
    const url = m[1]
    if (url.includes('deepseek')) return 'deepseek'
    if (url.includes('dashscope') || url.includes('aliyuncs')) return 'qwen'
    if (url.includes('bigmodel')) return 'glm'
    if (url.includes('minimaxi')) return 'minimax'
    if (url.includes('aixor')) return 'aixor'
    if (url.includes('localhost:20128')) return 'omniroute'
    return 'unknown'
  } catch { return 'unknown' }
}

function getCurrentModel(): string {
  try {
    if (!fs.existsSync(CLAUDE_SETTINGS)) return 'unknown'
    const content = fs.readFileSync(CLAUDE_SETTINGS, 'utf-8')
    const m = content.match(/"ANTHROPIC_MODEL":\s*"([^"]+)"/)
    return m ? m[1] : 'unknown'
  } catch { return 'unknown' }
}

function backupSettings(): void {
  fs.mkdirSync(BACKUP_DIR, { recursive: true })
  const ts = new Date().toISOString().replace(/[:.]/g, '')
  const backupPath = `${BACKUP_DIR}/settings.json.backup.${ts}`
  if (fs.existsSync(CLAUDE_SETTINGS)) {
    fs.copyFileSync(CLAUDE_SETTINGS, backupPath)
    logInfo(`已备份到: ${backupPath}`)
  }
}

async function readExistingToken(provider: string): Promise<string> {
  const key = PROVIDERS[provider]?.key
  if (!key) return ''
  try {
    if (!fs.existsSync(CLAUDE_SETTINGS)) return ''
    const content = fs.readFileSync(CLAUDE_SETTINGS, 'utf-8')
    const m = content.match(new RegExp(`"${key}":\\s*"([^"]+)"`))
    return m ? m[1] : ''
  } catch { return '' }
}

function writeSettings(provider: string, model: string, token: string): void {
  const def = PROVIDERS[provider]
  const maxTokens = model.includes('coder') ? '16384' : model.includes('max') ? '32768' : '8192'

  const settings = {
    env: {
      [def.key]: token,
      ANTHROPIC_BASE_URL: def.url,
      ANTHROPIC_MODEL: model,
      ANTHROPIC_DEFAULT_OPUS_MODEL: model,
      ANTHROPIC_DEFAULT_SONNET_MODEL: model,
      ANTHROPIC_DEFAULT_HAIKU_MODEL: model,
      CLAUDE_CODE_SUBAGENT_MODEL: model,
      CLAUDE_CODE_MAX_OUTPUT_TOKENS: maxTokens,
      CLAUDE_CODE_EFFORT_LEVEL: 'max',
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: '1',
      CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK: '1',
      CLAUDE_CODE_ATTRIBUTION_HEADER: '0',
      ENABLE_TOOL_SEARCH: '1',
      DISABLE_EXTRA_USAGE_COMMAND: '1',
    },
  }

  fs.writeFileSync(CLAUDE_SETTINGS, JSON.stringify(settings, null, 2) + '\n')
  logInfo(`配置已更新: ${provider} / ${model}`)
  logInfo('重启 Claude Code 生效')
}

export async function cmdModelSwitch(args: string[]): Promise<void> {
  const sub = args[0]

  if (sub === 'list') {
    printHeader()
    console.log('')
    console.log('支持的提供商 (2026年6月最新):')
    console.log('')
    for (const [name, def] of Object.entries(PROVIDERS)) {
      console.log(`  ★ ${name}`)
      console.log(`    URL:    ${def.url}`)
      console.log(`    Key:    ${def.key}`)
      console.log(`    模型:   ${def.models.join(', ')}`)
      console.log('')
    }
    return
  }

  if (sub === 'status') {
    printHeader()
    console.log('')
    console.log('--- 当前配置 ---')
    if (!fs.existsSync(CLAUDE_SETTINGS)) {
      console.log('未找到配置文件')
      return
    }
    console.log(`  提供商: ${getCurrentProvider()}`)
    console.log(`  模型:   ${getCurrentModel()}`)
    return
  }

  if (sub === 'backup') {
    printHeader()
    backupSettings()
    return
  }

  if (sub === 'switch') {
    printHeader()
    const providerName = args[1]
    const modelArg = args[2]

    if (!providerName) {
      logError('请指定提供商')
      console.log('用法: rinbake model-switch switch <provider> [model]')
      return
    }

    const provider = PROVIDERS[providerName]
    if (!provider) {
      logError(`未知提供商: ${providerName}`)
      console.log(`支持: ${Object.keys(PROVIDERS).join(', ')}`)
      return
    }

    let model = modelArg || provider.models[0]
    if (modelArg && !provider.models.includes(modelArg)) {
      logError(`模型 '${modelArg}' 无效，可用: ${provider.models.join(', ')}`)
      return
    }

    backupSettings()

    if (providerName === 'omniroute') await ensureReady()

    let token = await readExistingToken(providerName)
    if (!token && providerName !== 'omniroute') {
      const tokenInput = await input({ message: `请输入 API Token (${provider.key}):` })
      if (typeof tokenInput !== 'string' || !tokenInput.trim()) {
        logError('Token 不能为空')
        return
      }
      token = tokenInput.trim()
    }

    writeSettings(providerName, model, token)
    return
  }

  // Interactive mode
  intro(color.bgCyan(' rinbake model-switch '))

  const providerNames = Object.keys(PROVIDERS)
  const providerChoice = await select({
    message: '选择提供商',
    options: providerNames.map(n => ({ value: n, label: n })),
  })
  if (isCancelled(providerChoice) || typeof providerChoice !== 'string') { outro('已取消'); return }

  const def = PROVIDERS[providerChoice]
  const modelChoice = await select({
    message: '选择模型',
    options: def.models.map(m => ({ value: m, label: m })),
  })
  if (isCancelled(modelChoice) || typeof modelChoice !== 'string') { outro('已取消'); return }

  backupSettings()
  let token = await readExistingToken(providerChoice)
  if (!token) {
    const tokenInput = await input({ message: `请输入 API Token (${def.key}):` })
    if (typeof tokenInput !== 'string' || !tokenInput.trim()) { outro('已取消'); return }
    token = tokenInput.trim()
  }

  writeSettings(providerChoice, modelChoice, token)
  outro('完成')
}
