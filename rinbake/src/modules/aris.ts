import { $ } from 'bun'
import * as fs from 'node:fs'
import { hasCommand } from '../utils'
import { logStep, logInfo, logWarn, confirm } from '../utils/ui'
import { promptAndSetKey } from '../config/keys'

export const id = 'aris'
export const label = 'ARIS (Auto-Research-In-Sleep)'
export const description = 'AI 自动调研，文献综述 + 迭代优化'
export const category = 'agent' as const
export const enabled = false

const ARIS_REPO = 'https://github.com/wanshuiyin/Auto-claude-code-research-in-sleep.git'
const ARIS_DIR = `${process.env.HOME || '/root'}/.local/share/aris`
const SKILLS_TARGET = `${process.env.HOME || '/root'}/.claude/skills`
const CLAUDE_SETTINGS = `${process.env.HOME || '/root'}/.claude/settings.json`
const CODEX_CFG = `${process.env.HOME || '/root'}/.codex/config.toml`

export async function install(): Promise<void> {
  logStep('克隆/更新 ARIS 仓库...')
  await $`mkdir -p ${ARIS_DIR}`.nothrow()
  const isRepo = fs.existsSync(`${ARIS_DIR}/.git`)
  if (isRepo) {
    const result = await $`git -C ${ARIS_DIR} pull --ff-only`.nothrow()
    if (result.exitCode !== 0) logWarn('git pull 失败，继续使用现有副本')
  } else {
    const result = await $`git clone ${ARIS_REPO} ${ARIS_DIR}`.nothrow()
    if (result.exitCode !== 0) {
      logWarn('克隆失败，跳过 ARIS')
      return
    }
  }

  logStep('安装 ARIS skills...')
  await $`mkdir -p ${SKILLS_TARGET}`.nothrow()
  if (fs.existsSync(`${ARIS_DIR}/tools/install_aris.sh`)) {
    const result = await $`bash ${ARIS_DIR}/tools/install_aris.sh`.nothrow()
    if (result.exitCode !== 0) {
      logWarn('install_aris.sh 失败，尝试直接复制 skills')
      copySkills()
    }
  } else {
    copySkills()
  }

  await setSkillsDirectory()
  await configureCodexMcp()
  await configureArisMcpServers()
  await setupEnvFile()

  logInfo('ARIS 安装完成')
  console.log('')
  console.log(`  ARIS 仓库: ${ARIS_DIR}`)
  console.log(`  Skills:    ${SKILLS_TARGET}`)
  console.log('')
  console.log('  Next steps:')
  console.log('  1. Restart Claude Code')
  console.log('  2. /idea-discovery "topic" — 文献调研')
  console.log('  3. /auto-review-loop "topic" — 迭代优化')
  console.log('  4. /research-pipeline "topic" — 完整流程')
}

function copySkills(): void {
  const skillsSrc = `${ARIS_DIR}/skills`
  if (!fs.existsSync(skillsSrc)) {
    logWarn('ARIS 仓库无 skills/ 目录')
    return
  }
  const before = fs.readdirSync(SKILLS_TARGET).length
  fs.cpSync(skillsSrc, SKILLS_TARGET, { recursive: true })
  const after = fs.readdirSync(SKILLS_TARGET).length
  logInfo(`Skills 已复制到 ${SKILLS_TARGET} (新增 ${after - before} 目录)`)
}

async function setSkillsDirectory(): Promise<void> {
  if (!fs.existsSync(CLAUDE_SETTINGS)) return
  try {
    const settings = JSON.parse(fs.readFileSync(CLAUDE_SETTINGS, 'utf-8'))
    if (settings.skillsDirectory !== SKILLS_TARGET) {
      settings.skillsDirectory = SKILLS_TARGET
      fs.writeFileSync(CLAUDE_SETTINGS, JSON.stringify(settings, null, 2) + '\n')
      logInfo('skillsDirectory 已更新')
    }
  } catch {}
}

async function configureCodexMcp(): Promise<void> {
  if (!(await hasCommand('codex'))) return
  const doCodex = await confirm({ message: '添加 codex MCP server（ARIS review skill 需要）？', defaultValue: false })
  if (doCodex !== true) return

  await $`mkdir -p ${CODEX_CFG.replace(/\/[^/]+$/, '')}`.nothrow()
  try {
    let text = ''
    if (fs.existsSync(CODEX_CFG)) {
      text = fs.readFileSync(CODEX_CFG, 'utf-8')
    }
    const tableRe = /^\s*\[([^\]]+)\]\s*$/m
    const lines = text.split('\n')
    const out: string[] = []
    let skip = false
    for (const line of lines) {
      const match = line.match(tableRe)
      if (match) {
        skip = match[1] === 'mcp_servers.codex'
      }
      if (!skip) out.push(line)
    }
    while (out.length > 0 && !out[out.length - 1].trim()) out.pop()
    out.push('', '[mcp_servers.codex]', 'command = "codex"', 'args = ["mcp-server"]', '')
    fs.writeFileSync(CODEX_CFG, out.join('\n'))
    logInfo(`Codex MCP server 已添加到 ${CODEX_CFG}`)
  } catch (e) {
    logWarn(`写入 Codex 配置失败: ${e}`)
  }
}

async function configureArisMcpServers(): Promise<void> {
  const braveKey = await promptAndSetKey('BRAVE_API_KEY', 'BRAVE_API_KEY (留空跳过 brave-search)')
  if (!fs.existsSync(CLAUDE_SETTINGS)) return

  try {
    const settings = JSON.parse(fs.readFileSync(CLAUDE_SETTINGS, 'utf-8'))
    const mcp = settings.mcpServers || {}

    if (braveKey && !mcp['brave-search']) {
      mcp['brave-search'] = {
        command: 'npx',
        args: ['-y', '@anthropic-ai/mcp-server-brave-search'],
        env: { BRAVE_API_KEY: braveKey },
      }
    }
    if (!mcp.context7) {
      mcp.context7 = { command: 'npx', args: ['-y', 'context7'] }
    }
    if (!mcp.puppeteer) {
      mcp.puppeteer = { command: 'npx', args: ['-y', '@anthropic-ai/mcp-server-puppeteer'] }
    }

    settings.mcpServers = mcp
    fs.writeFileSync(CLAUDE_SETTINGS, JSON.stringify(settings, null, 2) + '\n')
    logInfo(`ARIS MCP servers 已写入 ${CLAUDE_SETTINGS}`)
  } catch {}
}

async function setupEnvFile(): Promise<void> {
  const envExample = `${ARIS_DIR}/.env.example`
  const envFile = `${ARIS_DIR}/.env`
  if (!fs.existsSync(envExample) || fs.existsSync(envFile)) return
  const doCopy = await confirm({ message: '从 .env.example 创建 .env？', defaultValue: false })
  if (doCopy === true) {
    fs.copyFileSync(envExample, envFile)
    logInfo(`已创建 ${envFile} — 编辑添加 API Key`)
  }
}

export async function detect(): Promise<boolean> {
  return fs.existsSync(`${ARIS_DIR}/.git`)
}
