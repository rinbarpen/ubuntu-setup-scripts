import { $ } from 'bun'
import type { RinbakeConfig, ConfigProvider } from '../types'

const CONFIG_DIR = `${process.env.HOME || '/root'}/.config/rinbake`
const CONFIG_PATH = `${CONFIG_DIR}/config.json`
const PROVIDERS_PATH = `${CONFIG_DIR}/providers.json`
const MCP_PATH = `${CONFIG_DIR}/mcp.json`
const INSTALLED_PATH = `${CONFIG_DIR}/installed.json`

async function ensureDir(): Promise<void> {
  await $`mkdir -p ${CONFIG_DIR}`.nothrow()
}

async function readJson<T>(path: string, fallback: T): Promise<T> {
  try {
    const file = Bun.file(path)
    if (await file.exists()) {
      return JSON.parse(await file.text()) as T
    }
  } catch {}
  return fallback
}

async function writeJson(path: string, data: unknown): Promise<void> {
  await ensureDir()
  await Bun.write(path, JSON.stringify(data, null, 2) + '\n')
}

export async function readConfig(): Promise<RinbakeConfig> {
  return readJson<RinbakeConfig>(CONFIG_PATH, { providers: {} })
}

export async function writeConfig(config: RinbakeConfig): Promise<void> {
  await writeJson(CONFIG_PATH, config)
}

export async function readProviders(): Promise<Record<string, ConfigProvider>> {
  return readJson<Record<string, ConfigProvider>>(PROVIDERS_PATH, {})
}

export async function writeProviders(providers: Record<string, ConfigProvider>): Promise<void> {
  await writeJson(PROVIDERS_PATH, providers)
}

export async function readInstalled(): Promise<string[]> {
  return readJson<string[]>(INSTALLED_PATH, [])
}

export async function markInstalled(...ids: string[]): Promise<void> {
  const installed = await readInstalled()
  for (const id of ids) {
    if (!installed.includes(id)) installed.push(id)
  }
  await writeJson(INSTALLED_PATH, installed)
}

export async function writeMcpConfig(data: Record<string, unknown>): Promise<void> {
  await writeJson(MCP_PATH, data)
}

export async function readMcpConfig(): Promise<Record<string, unknown>> {
  return readJson<Record<string, unknown>>(MCP_PATH, {})
}
