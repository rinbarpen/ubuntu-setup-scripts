import type { McpServerDef } from '../../types'

const mcpRegistry: Record<string, McpServerDef> = {
  'context7': {
    id: 'context7',
    name: 'Context7 (代码上下文)',
    command: 'npx',
    args: ['-y', '@upstash/context7-mcp@latest'],
  },
  'brave-search': {
    id: 'brave-search',
    name: 'Brave Search (网络搜索)',
    command: 'npx',
    args: ['-y', '@modelcontextprotocol/server-brave-search'],
    env: { BRAVE_API_KEY: '{env:BRAVE_API_KEY}' },
  },
  'github': {
    id: 'github',
    name: 'GitHub (代码仓库)',
    command: 'npx',
    args: ['-y', '@modelcontextprotocol/server-github'],
    env: { GITHUB_PERSONAL_ACCESS_TOKEN: '{env:GITHUB_TOKEN}' },
  },
  'excalidraw': {
    id: 'excalidraw',
    name: 'Excalidraw (白板/图表)',
    command: 'npx',
    args: ['-y', '@anthropic-ai/mcp-server-excalidraw'],
  },
  'puppeteer': {
    id: 'puppeteer',
    name: 'Puppeteer (浏览器自动化)',
    command: 'npx',
    args: ['-y', '@modelcontextprotocol/server-puppeteer'],
  },
  'postgres': {
    id: 'postgres',
    name: 'PostgreSQL (数据库)',
    command: 'npx',
    args: ['-y', '@modelcontextprotocol/server-postgres'],
    env: { POSTGRES_DSN: '{env:POSTGRES_DSN}' },
  },
  'sqlite': {
    id: 'sqlite',
    name: 'SQLite (本地数据库)',
    command: 'npx',
    args: ['-y', '@modelcontextprotocol/server-sqlite', '--db-path', '{SQLITE_PATH}'],
  },
  'dev-chrome': {
    id: 'dev-chrome',
    name: 'Claude in Chrome (DevTools)',
    command: 'npx',
    args: ['-y', '@anthropic-ic/claude-in-chrome-mcp'],
  },
}

export function getMcpServers(selected: string[]): Record<string, McpServerDef> {
  if (selected.length === 0) return { ...mcpRegistry }
  const result: Record<string, McpServerDef> = {}
  for (const id of selected) {
    if (mcpRegistry[id]) result[id] = { ...mcpRegistry[id] }
  }
  return result
}

export function getAllMcpIds(): string[] {
  return Object.keys(mcpRegistry)
}

export function getMcpDef(id: string): McpServerDef | undefined {
  return mcpRegistry[id]
}
