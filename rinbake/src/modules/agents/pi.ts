import { $ } from 'bun'
import { hasCommand } from '../../utils'
import { logStep, logInfo, select, input, confirm } from '../../utils/ui'
import {
  selectAgentModel,
} from '../../config/agent-config'
import { getOmniRouteClientUrl, OMNIROUTE_API_KEY, OMNIROUTE_DEFAULT_MODEL } from '../../config/omniroute'

export const id = 'pi'
export const label = 'Pi Coding Agent'
export const description = '安装 Pi CLI (Armin Ronacher) 并通过 OmniRoute 配置模型、技能、扩展'
export const category = 'agent' as const
export const enabled = true

const PI_SETTINGS = `${process.env.HOME || '/root'}/.pi/agent/settings.json`
const PI_SKILLS = `${process.env.HOME || '/root'}/.pi/agent/skills`

export async function install(): Promise<void> {
  if (await hasCommand('pi')) {
    logStep('Pi 已安装')
  } else {
    logStep('安装 Pi...')
    await $`npm install -g @earendil-works/pi-coding-agent`.nothrow()
  }

  await configure()
}

export async function configure(): Promise<void> {
  const cfgDir = PI_SETTINGS.replace(/\/[^/]+$/, '')
  await $`mkdir -p ${cfgDir}`.nothrow()

  let settings: Record<string, unknown> = {}
  try {
    const f = Bun.file(PI_SETTINGS)
    if (await f.exists()) settings = JSON.parse(await f.text())
  } catch {}

  // Model
  const model = await selectAgentModel({ message: '选择默认模型', defaultModel: OMNIROUTE_DEFAULT_MODEL })
  if (model) settings.defaultModel = model
  settings.defaultProvider = 'omniroute'
  settings.baseUrl = getOmniRouteClientUrl('opencode')
  settings.apiKey = `{env:${OMNIROUTE_API_KEY}}`

  // Thinking level
  const thinkingOption = await select({
    message: '选择思考级别',
    options: [
      { value: 'medium', label: 'Medium', hint: '推荐' },
      { value: 'off', label: 'Off' },
      { value: 'minimal', label: 'Minimal' },
      { value: 'low', label: 'Low' },
      { value: 'high', label: 'High' },
      { value: 'xhigh', label: 'Extra High' },
      { value: 'max', label: 'Max' },
    ],
  })
  if (typeof thinkingOption === 'string' && thinkingOption !== 'medium') {
    settings.defaultThinkingLevel = thinkingOption
  }

  // Themes
  const themeOption = await select({
    message: '选择主题',
    options: [
      { value: 'dark', label: 'Dark', hint: '默认' },
      { value: 'light', label: 'Light' },
    ],
  })
  if (themeOption === 'light' || themeOption === 'dark') {
    settings.theme = themeOption
  }

  // Compaction
  const compactOption = await select({
    message: '自动压缩设置',
    options: [
      { value: 'default', label: '默认 (开启)', hint: 'enabled, 20k 保留' },
      { value: 'aggressive', label: '激进', hint: '16k 保留' },
      { value: 'off', label: '关闭' },
    ],
  })

  if (compactOption === 'aggressive') {
    settings.compaction = { enabled: true, reserveTokens: 16384, keepRecentTokens: 16000 }
  } else if (compactOption === 'off') {
    settings.compaction = { enabled: false }
  }

  // Proxy
  const useProxy = await confirm({ message: '配置 HTTP 代理？', defaultValue: false })
  if (useProxy === true) {
    const proxyUrl = await input({ message: 'HTTP 代理 URL', defaultValue: 'http://127.0.0.1:7890' })
    if (typeof proxyUrl === 'string' && proxyUrl.trim()) {
      settings.httpProxy = proxyUrl.trim()
    }
  }

  // Skills
  const setupSkills = await confirm({ message: '链接系统 Skills？', defaultValue: true })
  if (setupSkills === true) {
    await $`mkdir -p ${PI_SKILLS}`.nothrow()
    const homeAgentsSkills = `${process.env.HOME || '/root'}/.agents/skills`
    if (await $`test -d ${homeAgentsSkills}`.nothrow().then(r => r.exitCode === 0)) {
      const skillsList = await $`ls ${homeAgentsSkills}`.text().catch(() => '')
      if (skillsList.trim()) {
        await $`ln -sf ${homeAgentsSkills}/* ${PI_SKILLS}/`.nothrow()
        logInfo('系统 Skills 已链接')
      }
    }
  }

  // Write config
  await $`mkdir -p ${cfgDir}`.nothrow()
  await Bun.write(PI_SETTINGS, JSON.stringify(settings, null, 2) + '\n')
  logInfo(`Pi 配置已写入 ${PI_SETTINGS}`)
  logInfo(`运行 pi 启动（OmniRoute: ${getOmniRouteClientUrl('opencode')}；如未运行请执行 rinbake omniroute start）`)
}

export async function detect(): Promise<boolean> {
  return hasCommand('pi')
}
