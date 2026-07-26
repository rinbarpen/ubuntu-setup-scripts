import { $ } from 'bun'
import { hasCommand } from '../../utils'
import { logStep, logInfo, select, input, confirm } from '../../utils/ui'
import { promptAndSetKey } from '../../config/keys'
import {
  selectAgentModel, selectAgentProvider, selectAgentMcpServers, selectAgentPlanModel, selectAgentRelay,
} from '../../config/agent-config'

export const id = 'omp'
export const label = 'OMP (Oh My Pi) Coding Agent'
export const description = '安装 OMP CLI (Pi fork) 并配置模型、LSP、调试器、MCP'
export const category = 'agent' as const
export const enabled = true

const OMP_CONFIG = `${process.env.HOME || '/root'}/.omp/agent/settings.json`

export async function install(): Promise<void> {
  if (await hasCommand('omp')) {
    logStep('OMP 已安装')
  } else {
    logStep('安装 OMP...')
    await $`npm install -g @oh-my-pi/pi-coding-agent`.nothrow()
  }

  await configure()
}

export async function configure(): Promise<void> {
  const cfgDir = OMP_CONFIG.replace(/\/[^/]+$/, '')
  await $`mkdir -p ${cfgDir}`.nothrow()

  let config: Record<string, unknown> = {}
  try {
    const f = Bun.file(OMP_CONFIG)
    if (await f.exists()) config = JSON.parse(await f.text())
  } catch {}

  // Model & roles
  const model = await selectAgentModel({ message: 'OMP: 选择默认模型' })
  if (model && model !== 'custom') config.defaultModel = model

  const slowModel = await selectAgentModel({ message: 'OMP: 选择 Slow 模型 (重任务)' })
  if (slowModel && typeof slowModel === 'string' && slowModel !== 'custom' && slowModel !== model) {
    config.slowModel = slowModel
  }

  const planModel = await selectAgentPlanModel({ message: 'OMP: 选择 Plan 模型' })
  if (planModel && planModel !== 'skip') config.planModel = planModel

  const smolModel = await selectAgentModel({ message: 'OMP: 选择 Smol 模型 (轻任务)' })
  if (smolModel && typeof smolModel === 'string' && smolModel !== 'custom' && smolModel !== model) {
    config.smolModel = smolModel
  }

  // Provider
  const provider = await selectAgentProvider({ message: 'OMP: 选择供应商' })
  if (provider) config.defaultProvider = provider.id

  // Thinking
  const thinkingOption = await select({
    message: 'OMP: 选择思考级别',
    options: [
      { value: 'medium', label: 'Medium', hint: '推荐' },
      { value: 'off', label: 'Off' },
      { value: 'minimal', label: 'Minimal' },
      { value: 'low', label: 'Low' },
      { value: 'high', label: 'High' },
      { value: 'xhigh', label: 'Extra High' },
    ],
  })
  if (typeof thinkingOption === 'string' && thinkingOption !== 'medium') {
    config.defaultThinkingLevel = thinkingOption
  }

  // LSP
  const enableLsp = await confirm({ message: '启用 LSP (代码智能)？', defaultValue: true })
  config.lsp = { enabled: enableLsp === true }

  // DAP (debugger)
  const enableDap = await confirm({ message: '启用 DAP (调试器)？', defaultValue: false })
  config.dap = { enabled: enableDap === true }

  // Features
  const modeOption = await select({
    message: 'OMP: 选择运行模式',
    options: [
      { value: 'default', label: '默认', hint: '完整功能' },
      { value: 'plan', label: 'Plan Mode', hint: '先计划后执行' },
      { value: 'goal', label: 'Goal Mode', hint: '目标驱动' },
    ],
  })
  if (modeOption === 'plan') config.defaultMode = 'plan'
  if (modeOption === 'goal') config.defaultMode = 'goal'

  // Theme
  const themeOption = await select({
    message: 'OMP: 选择主题',
    options: [
      { value: 'dark', label: 'Dark', hint: '默认' },
      { value: 'light', label: 'Light' },
    ],
  })
  if (themeOption === 'light' || themeOption === 'dark') config.theme = themeOption

  // Proxy
  const useProxy = await confirm({ message: '配置 HTTP 代理？', defaultValue: false })
  if (useProxy === true) {
    const proxyUrl = await input({ message: 'HTTP 代理 URL', defaultValue: 'http://127.0.0.1:7890' })
    if (typeof proxyUrl === 'string' && proxyUrl.trim()) {
      config.httpProxy = proxyUrl.trim()
    }
  }

  // Skills
  const skillsDir = `${process.env.HOME || '/root'}/.omp/agent/skills`
  const setupSkills = await confirm({ message: '链接系统 Skills？', defaultValue: true })
  if (setupSkills === true) {
    await $`mkdir -p ${skillsDir}`.nothrow()
    const homeAgentsSkills = `${process.env.HOME || '/root'}/.agents/skills`
    if (await $`test -d ${homeAgentsSkills}`.nothrow().then(r => r.exitCode === 0)) {
      const skillsList = await $`ls ${homeAgentsSkills}`.text().catch(() => '')
      if (skillsList.trim()) {
        await $`ln -sf ${homeAgentsSkills}/* ${skillsDir}/`.nothrow()
        logInfo('系统 Skills 已链接')
      }
    }
  }

  // Agent definitions
  const setupAgents = await confirm({ message: '解压内置 subagent 定义？', defaultValue: false })
  if (setupAgents === true) {
    await $`omp agents unpack`.nothrow()
    logInfo('Subagent 定义已解压')
  }

  // Write config
  await $`mkdir -p ${cfgDir}`.nothrow()
  await Bun.write(OMP_CONFIG, JSON.stringify(config, null, 2) + '\n')
  logInfo(`OMP 配置已写入 ${OMP_CONFIG}`)
  logInfo('运行 omp 启动 (需先设置 API Key 环境变量)')
}

export async function detect(): Promise<boolean> {
  return hasCommand('omp')
}
