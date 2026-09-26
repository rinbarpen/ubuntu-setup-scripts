import { $ } from 'bun'
import * as fs from 'node:fs'
import * as path from 'node:path'
import crypto from 'node:crypto'
import { hasCommand, targetHome } from '../utils'
import { logStep, logInfo, logWarn, logError, input, confirm } from '../utils/ui'

export const id = 'overleaf'
export const label = 'Overleaf (ShareLaTeX)'
export const description = '自托管 Overleaf LaTeX 协作平台 (Docker)'
export const category = 'other' as const
export const scope = 'user' as const
export const enabled = false

const SCRIPT_DIR = path.resolve(import.meta.dir, '../../..')
const OVERLEAF_DIR = path.resolve(SCRIPT_DIR, 'overleaf')

export async function install(): Promise<void> {
  const running = await $`docker ps -a --format '{{.Names}}' 2>/dev/null | grep '^overleaf$'`.nothrow()
  if (running.exitCode === 0) {
    logInfo('Overleaf 容器已在运行')
    const recreate = await confirm({ message: '重新创建 Overleaf 容器？', defaultValue: false })
    if (recreate !== true) { logInfo('overleaf: 跳过'); return }
    logStep('停止现有容器...')
    await $`docker compose -f ${OVERLEAF_DIR}/docker-compose.yml down`.nothrow()
  }

  await $`mkdir -p ${OVERLEAF_DIR}`.nothrow()

  const env: Record<string, string> = {}
  const envPath = `${OVERLEAF_DIR}/.env`
  if (fs.existsSync(envPath)) {
    const content = fs.readFileSync(envPath, 'utf-8')
    for (const line of content.split('\n')) {
      const m = line.match(/^OVERLEAF_(\w+)=(.*)$/)
      if (m) env[`OVERLEAF_${m[1]}`] = m[2].replace(/^['"](.*)['"]$/, '$1')
    }
  }

  const defaults: Record<string, string> = {
    OVERLEAF_SITE_URL: 'http://localhost:25681',
    OVERLEAF_APP_NAME: 'Overleaf @Rczx',
    OVERLEAF_PORT: '25681',
    OVERLEAF_MONGO_URL: 'mongodb://mongo/sharelatex',
    OVERLEAF_EMAIL: '',
    OVERLEAF_INVITE_TOKEN_SECRET: crypto.randomBytes(32).toString('base64'),
    OVERLEAF_IMAGE: 'sharelatex/sharelatex:with-texlive',
  }

  for (const [k, v] of Object.entries(defaults)) {
    if (!env[k]) env[k] = v
  }

  const urlInput = await input({ message: 'Overleaf 公网 URL', defaultValue: env.OVERLEAF_SITE_URL })
  if (typeof urlInput === 'string' && urlInput.trim()) env.OVERLEAF_SITE_URL = urlInput.trim()

  const nameInput = await input({ message: '显示名称', defaultValue: env.OVERLEAF_APP_NAME })
  if (typeof nameInput === 'string' && nameInput.trim()) env.OVERLEAF_APP_NAME = nameInput.trim()

  const portInput = await input({ message: '主机端口', defaultValue: env.OVERLEAF_PORT })
  if (typeof portInput === 'string' && portInput.trim()) env.OVERLEAF_PORT = portInput.trim()

  if (await hasCommand('lsof')) {
    const portCheck = await $`lsof -ti :${env.OVERLEAF_PORT} 2>/dev/null`.nothrow()
    if (portCheck.exitCode === 0 && portCheck.stdout.toString().trim()) {
      logWarn(`端口 ${env.OVERLEAF_PORT} 已被占用 (PID: ${portCheck.stdout.toString().trim()})`)
      const cont = await confirm({ message: '继续？', defaultValue: false })
      if (cont !== true) { logError('中止'); return }
    }
  }

  const emailInput = await input({ message: '管理员邮箱 (可选)' })
  if (typeof emailInput === 'string' && emailInput.trim()) env.OVERLEAF_EMAIL = emailInput.trim()

  const doSmtp = await confirm({ message: '配置 SMTP 邮件？', defaultValue: false })
  if (doSmtp === true) {
    const smtpHost = await input({ message: 'SMTP 主机' })
    if (typeof smtpHost === 'string' && smtpHost.trim()) env.OVERLEAF_EMAIL_SMTP_HOST = smtpHost.trim()

    const smtpPort = await input({ message: 'SMTP 端口', defaultValue: env.OVERLEAF_EMAIL_SMTP_PORT || '587' })
    if (typeof smtpPort === 'string' && smtpPort.trim()) env.OVERLEAF_EMAIL_SMTP_PORT = smtpPort.trim()

    const smtpUser = await input({ message: 'SMTP 用户' })
    if (typeof smtpUser === 'string' && smtpUser.trim()) env.OVERLEAF_EMAIL_SMTP_USER = smtpUser.trim()

    const smtpPass = await input({ message: 'SMTP 密码' })
    if (typeof smtpPass === 'string' && smtpPass.trim()) env.OVERLEAF_EMAIL_SMTP_PASS = smtpPass.trim()

    const doTls = await confirm({ message: '使用 TLS?' })
    env.OVERLEAF_EMAIL_SMTP_SECURE = doTls === true ? 'true' : 'false'

    const fromAddr = await input({ message: '发件地址' })
    if (typeof fromAddr === 'string' && fromAddr.trim()) env.OVERLEAF_EMAIL_FROM_ADDRESS = fromAddr.trim()
  }

  const doTexlive = await confirm({ message: '安装完整 TeX Live (~5GB)？', defaultValue: false })
  env.OVERLEAF_INSTALL_TEXLIVE = doTexlive === true ? 'true' : 'false'

  const doCjk = await confirm({ message: '安装 CJK 字体 (Noto CJK)？', defaultValue: false })
  env.OVERLEAF_INSTALL_CJK = doCjk === true ? 'true' : 'false'

  const doXelatex = await confirm({ message: '安装 XeLaTeX 支持？', defaultValue: false })
  env.OVERLEAF_INSTALL_XELATEX = doXelatex === true ? 'true' : 'false'

  function quote(s: string): string {
    if (!s) return '""'
    if (/[\s#'"$`\\]/.test(s)) return `'${s.replace(/'/g, "'\\''")}'`
    return s
  }

  const envLines = [
    'OVERLEAF_SITE_URL', 'OVERLEAF_APP_NAME', 'OVERLEAF_PORT',
    'OVERLEAF_MONGO_URL', 'OVERLEAF_EMAIL', 'OVERLEAF_INVITE_TOKEN_SECRET',
    'OVERLEAF_LEFT_FOOTER', 'OVERLEAF_RIGHT_FOOTER', 'OVERLEAF_IMAGE',
    'OVERLEAF_EMAIL_FROM_ADDRESS', 'OVERLEAF_EMAIL_SMTP_HOST',
    'OVERLEAF_EMAIL_SMTP_PORT', 'OVERLEAF_EMAIL_SMTP_SECURE',
    'OVERLEAF_EMAIL_SMTP_USER', 'OVERLEAF_EMAIL_SMTP_PASS',
    'OVERLEAF_EMAIL_SMTP_TLS_REJECT_UNAUTH', 'OVERLEAF_EMAIL_SMTP_IGNORE_TLS',
  ]

  const envOut = envLines.map(k => `${k}=${quote(env[k] || '')}`).join('\n')
  fs.writeFileSync(envPath, envOut + '\n')
  await $`chmod 600 ${envPath}`.nothrow()
  logInfo(`.env 已写入 ${envPath}`)

  logStep('启动 Overleaf...')
  const upResult = await $`docker compose -f ${OVERLEAF_DIR}/docker-compose.yml up -d`.nothrow()
  if (upResult.exitCode !== 0) {
    logError('docker compose up 失败')
    return
  }

  logStep('等待 Overleaf 就绪（最长 180s）...')
  for (let elapsed = 0; elapsed < 180; elapsed += 5) {
    const curlResult = await $`curl -sf http://localhost:${env.OVERLEAF_PORT} >/dev/null 2>&1`.nothrow()
    if (curlResult.exitCode === 0) {
      logInfo(`Overleaf 就绪: http://localhost:${env.OVERLEAF_PORT}`)
      break
    }
    await new Promise(r => setTimeout(r, 5000))
  }

  if (env.OVERLEAF_INSTALL_TEXLIVE === 'true') {
    logStep('安装 TeX Live (约 30 分钟)...')
    await $`docker compose exec -T sharelatex tlmgr install scheme-full 2>&1 | tail -5`.nothrow()
  }
  if (env.OVERLEAF_INSTALL_CJK === 'true') {
    logStep('安装 CJK 字体...')
    await $`docker compose exec -T sharelatex bash -c "apt-get update -qq && apt-get install -y -qq fonts-noto-cjk && fc-cache -fv"`.nothrow()
  }
  if (env.OVERLEAF_INSTALL_XELATEX === 'true') {
    logStep('安装 XeLaTeX...')
    await $`docker compose exec -T sharelatex bash -c "command -v xelatex || apt-get install -y -qq texlive-xetex"`.nothrow()
  }

  const anyExtra = env.OVERLEAF_INSTALL_TEXLIVE === 'true' || env.OVERLEAF_INSTALL_CJK === 'true' || env.OVERLEAF_INSTALL_XELATEX === 'true'
  if (anyExtra) {
    const doCommit = await confirm({ message: '提交容器为 overleaf-custom:latest 以持久化？', defaultValue: false })
    if (doCommit === true) {
      await $`docker commit overleaf overleaf-custom:latest`.nothrow()
      logInfo('已提交 overleaf-custom:latest')
      const newEnv = fs.readFileSync(envPath, 'utf-8').replace(/^OVERLEAF_IMAGE=.*/m, 'OVERLEAF_IMAGE=overleaf-custom:latest')
      fs.writeFileSync(envPath, newEnv)
      logInfo('.env 已更新为 overleaf-custom:latest')
    }
  }

  await writeShellHelpers(env.OVERLEAF_PORT)
  printNextSteps(env.OVERLEAF_PORT, env.OVERLEAF_SITE_URL)
}

async function writeShellHelpers(port: string): Promise<void> {
  const fishDir = `${targetHome()}/.config/fish/functions`
  await $`mkdir -p ${fishDir}`.nothrow()

  const fishContent = `function overleaf-compose
    docker compose -f ${OVERLEAF_DIR}/docker-compose.yml $argv
end
function overleaf-logs;   overleaf-compose logs -f $argv; end
function overleaf-restart; overleaf-compose restart $argv; end
function overleaf-shell;   overleaf-compose exec sharelatex bash; end
function overleaf-ps;      overleaf-compose ps; end
function overleaf-up;      overleaf-compose up -d; end
function overleaf-down;    overleaf-compose down; end
function overleaf-update;  overleaf-compose pull && overleaf-compose up -d; end`

  await Bun.write(`${fishDir}/overleaf.fish`, `function overleaf-compose\n    docker compose -f ${OVERLEAF_DIR}/docker-compose.yml $argv\nend\n`)

  const bashrc = `${targetHome()}/.bashrc`
  const bashContent = fs.existsSync(bashrc) ? fs.readFileSync(bashrc, 'utf-8') : ''
  if (!bashContent.includes('# overleaf (added by setup)')) {
    const append = `
# overleaf (added by setup)
OVERLEAF_COMPOSE="${OVERLEAF_DIR}/docker-compose.yml"
overleaf-compose() { docker compose -f "$OVERLEAF_COMPOSE" "$@"; }
overleaf-logs()    { overleaf-compose logs -f "$@"; }
overleaf-restart() { overleaf-compose restart "$@"; }
overleaf-shell()   { overleaf-compose exec sharelatex bash; }
overleaf-ps()      { overleaf-compose ps; }
overleaf-up()      { overleaf-compose up -d; }
overleaf-down()    { overleaf-compose down; }
overleaf-update()  { overleaf-compose pull && overleaf-compose up -d; }
`
    fs.appendFileSync(bashrc, append)
  }
}

function printNextSteps(port: string, siteUrl: string): void {
  logInfo('overleaf: 完成')
  console.log('')
  console.log(`  URL:         ${siteUrl}`)
  console.log(`  配置目录:    ${OVERLEAF_DIR}`)
  console.log('')
  console.log('  首次使用:')
  console.log(`  1. 打开 ${siteUrl}`)
  console.log('  2. 创建管理员账号（首注册用户自动成为管理员）')
  console.log('')
}

export async function detect(): Promise<boolean> {
  const ps = await $`docker ps -a --format '{{.Names}}' 2>/dev/null | grep '^overleaf$'`.nothrow()
  return ps.exitCode === 0
}
