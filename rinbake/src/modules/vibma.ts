import { $ } from 'bun'
import * as fs from 'node:fs'
import * as path from 'node:path'
import { hasCommand } from '../utils'
import { logStep, logInfo, logWarn, logError, confirm } from '../utils/ui'

export const id = 'vibma'
export const label = 'Vibma MCP + Figma Plugin'
export const description = 'Vibma MCP 桥接 + Figma 插件 + Skills'
export const category = 'other' as const
export const enabled = false

const DEFAULT_PORT = 3055
const SCRIPT_DIR = path.resolve(import.meta.dir, '../../..')

export async function install(): Promise<void> {
  const port = await resolvePort()

  await downloadPlugin()
  await writeClaudeMcp(port)
  await writeCodexMcp(port)
  await installSkills()

  logInfo('Vibma 安装完成')
  console.log('')
  console.log('Next steps:')
  console.log(`  1. 启动隧道: VIBMA_PORT=${port} npx @ufira/vibma-tunnel@latest`)
  console.log('  2. 在 Figma 插件 UI 中设置:')
  console.log(`     Port: ${port}`)
  console.log('     Channel: vibma')
  console.log('  3. 重启 AI 工具，然后运行:')
  console.log('     connection(method: "create")')
  console.log('     connection(method: "get")')
}

async function resolvePort(): Promise<number> {
  const lsofCheck = await $`lsof -ti :${DEFAULT_PORT} 2>/dev/null`.nothrow()
  if (lsofCheck.exitCode !== 0) return DEFAULT_PORT

  logWarn(`端口 ${DEFAULT_PORT} 已被占用`)
  const killChoice = await confirm({ message: `终止占用 ${DEFAULT_PORT} 的进程？`, defaultValue: false })
  if (killChoice === true) {
    const pids = lsofCheck.stdout.toString().trim().split('\n')
    for (const pid of pids) {
      if (pid.trim()) await $`kill ${pid.trim()}`.nothrow()
    }
    await new Promise(r => setTimeout(r, 1000))
    const recheck = await $`lsof -ti :${DEFAULT_PORT} 2>/dev/null`.nothrow()
    if (recheck.exitCode !== 0) return DEFAULT_PORT
    logError('无法释放端口')
  }

  for (const candidate of [3056, 3057, 3058]) {
    const c = await $`lsof -ti :${candidate} 2>/dev/null`.nothrow()
    if (c.exitCode !== 0) return candidate
  }

  logError('端口 3055-3058 全部被占用，请释放一个后重试')
  process.exit(1)
}

async function downloadPlugin(): Promise<void> {
  logStep('获取最新 release 信息...')
  const releaseJson = (await $`curl -fsSL https://api.github.com/repos/ufira-ai/vibma/releases/latest`).stdout.toString()
  let tag: string, pluginUrl: string
  try {
    const data = JSON.parse(releaseJson)
    tag = data.tag_name
    const asset = data.assets.find((a: { name: string }) => a.name === 'vibma-plugin.zip')
    if (!asset) throw new Error('vibma-plugin.zip not found in release assets')
    pluginUrl = asset.browser_download_url
  } catch (e) {
    logError(`解析 release 信息失败: ${e}`)
    return
  }

  const baseDir = `${process.env.HOME || '/root'}/.local/share/vibma/releases/${tag}`
  const zipPath = `${baseDir}/vibma-plugin.zip`
  const pluginDir = `${baseDir}/plugin`

  await $`mkdir -p ${baseDir}`.nothrow()
  logInfo(`下载 vibma-plugin.zip (${tag})...`)
  await $`curl -fL ${pluginUrl} -o ${zipPath}`.nothrow()

  fs.rmSync(pluginDir, { recursive: true, force: true })
  await $`mkdir -p ${pluginDir}`.nothrow()
  await $`unzip -q -o ${zipPath} -d ${pluginDir}`.nothrow()

  const manifestPath = `${pluginDir}/manifest.json`
  if (!fs.existsSync(manifestPath)) {
    logError(`manifest.json 未找到: ${manifestPath}`)
    return
  }

  logInfo(`插件已解压到: ${pluginDir}`)
  logInfo(`Figma 中加载此 manifest: ${manifestPath}`)
}

async function writeClaudeMcp(port: number): Promise<void> {
  const claudeSettings = `${process.env.HOME || '/root'}/.claude/settings.json`
  await $`mkdir -p ${path.dirname(claudeSettings)}`.nothrow()

  let settings: Record<string, unknown> = {}
  try {
    if (fs.existsSync(claudeSettings)) settings = JSON.parse(fs.readFileSync(claudeSettings, 'utf-8'))
  } catch {}

  const mcp = (settings.mcpServers as Record<string, unknown>) || {}
  mcp['Vibma'] = {
    command: 'npx',
    args: ['-y', '@ufira/vibma@latest', '--edit', `--port=${port}`],
  }
  settings.mcpServers = mcp

  fs.writeFileSync(claudeSettings, JSON.stringify(settings, null, 2) + '\n')
  logInfo(`Claude MCP server 'Vibma' 已写入 ${claudeSettings}`)
}

async function writeCodexMcp(port: number): Promise<void> {
  const codexCfg = `${process.env.HOME || '/root'}/.codex/config.toml`
  await $`mkdir -p ${path.dirname(codexCfg)}`.nothrow()

  try {
    let text = ''
    if (fs.existsSync(codexCfg)) text = fs.readFileSync(codexCfg, 'utf-8')
    const tableRe = /^\s*\[([^\]]+)\]\s*$/m
    const lines = text.split('\n')
    const out: string[] = []
    let skip = false
    for (const line of lines) {
      const match = line.match(tableRe)
      if (match) {
        const table = match[1]
        skip = table === `mcp_servers."Vibma"` || table === 'mcp_servers.Vibma'
      }
      if (!skip) out.push(line)
    }
    while (out.length > 0 && !out[out.length - 1].trim()) out.pop()

    out.push(
      '',
      `[mcp_servers."Vibma"]`,
      `command = "npx"`,
      `args = ["-y", "@ufira/vibma@latest", "--edit", "--port=${port}"]`,
      '',
    )
    fs.writeFileSync(codexCfg, out.join('\n'))
    logInfo(`Codex MCP server 'Vibma' 已写入 ${codexCfg}`)
  } catch {}
}

async function installSkills(): Promise<void> {
  const skillsSrc = `${SCRIPT_DIR}/scripts/skills`

  for (const dir of ['figma-vibma', 'figma-start-macos']) {
    const src = `${skillsSrc}/${dir}`
    if (!fs.existsSync(`${src}/SKILL.md`)) {
      logWarn(`缺少 skill 模板: ${src}/SKILL.md`)
      continue
    }

    for (const target of [`${process.env.HOME || '/root'}/.claude/skills`, `${process.env.HOME || '/root'}/.codex/skills`]) {
      const dest = `${target}/${dir}`
      if (fs.existsSync(dest)) {
        const backup = `${dest}.bak.${Date.now()}`
        fs.renameSync(dest, backup)
        logWarn(`已有 skill 已备份: ${backup}`)
      }
      await $`mkdir -p ${target}`.nothrow()
      fs.cpSync(src, dest, { recursive: true })
      logInfo(`Skill 已安装: ${dest}`)
    }
  }
}

export async function detect(): Promise<boolean> {
  const port = await $`lsof -ti :${DEFAULT_PORT} 2>/dev/null`.nothrow()
  return port.exitCode === 0
}
