import { $ } from 'bun'
import * as fs from 'node:fs'
import { hasCommand } from '../utils'
import { logStep, logInfo, logError } from '../utils/ui'

export const id = 'firecrawl'
export const label = 'Firecrawl'
export const description = 'Web 抓取工具 (Docker Compose)'
export const category = 'other' as const
export const enabled = false

export async function install(): Promise<void> {
  const firecrawlDir = process.env.FIRECRAWL_DIR || `${process.env.HOME || '/root'}/.local/share/firecrawl`
  const firecrawlPort = process.env.FIRECRAWL_PORT || '3002'

  logStep('Firecrawl Docker Compose 部署')

  await $`mkdir -p ${firecrawlDir}`.nothrow()

  const composePath = `${firecrawlDir}/docker-compose.yaml`
  if (fs.existsSync(composePath)) {
    logInfo('docker-compose.yaml 已存在')
  } else {
    logStep('下载 docker-compose.yaml...')
    const result = await $`curl -fsSL https://raw.githubusercontent.com/firecrawl/firecrawl/main/docker-compose.yaml -o ${composePath}`.nothrow()
    if (result.exitCode !== 0) {
      logError('下载 docker-compose.yaml 失败')
      return
    }
  }

  const envContent = `PORT=${firecrawlPort}
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=firecrawl
REDIS_URL=redis://redis:6379
LOGGING_LEVEL=info
`
  const envPath = `${firecrawlDir}/.env`
  if (!fs.existsSync(envPath)) {
    fs.writeFileSync(envPath, envContent)
    logInfo(`已创建 ${envPath}`)
  }

  logStep('启动 Firecrawl（首次构建可能需要 10-30 分钟）...')
  const upResult = await $`docker compose -f ${composePath} up -d`.nothrow()
  if (upResult.exitCode !== 0) {
    logError('docker compose up 失败')
    return
  }

  logStep('等待 Firecrawl 就绪...')
  for (let i = 1; i <= 60; i++) {
    const health = await $`curl -s -o /dev/null http://localhost:${firecrawlPort}/health 2>/dev/null`.nothrow()
    if (health.exitCode === 0) {
      logInfo(`Firecrawl 就绪: http://localhost:${firecrawlPort}`)
      break
    }
    await new Promise(r => setTimeout(r, 5000))
  }

  console.log('')
  logInfo('Firecrawl 部署完成')
  console.log(`  URL:     http://localhost:${firecrawlPort}`)
  console.log(`  配置:    ${envPath}`)
  console.log(`  Compose: ${composePath}`)
  console.log(`  管理:    docker compose -f ${composePath} {up|down|logs|ps}`)
}

export async function detect(): Promise<boolean> {
  const dir = process.env.FIRECRAWL_DIR || `${process.env.HOME || '/root'}/.local/share/firecrawl`
  return fs.existsSync(`${dir}/docker-compose.yaml`)
}
