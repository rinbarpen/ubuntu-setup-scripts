export interface ModuleDefinition {
  id: string
  label: string
  description: string
  category: 'system' | 'agent' | 'mcp' | 'other'
  enabled: boolean
  install: () => Promise<void>
  configure?: () => Promise<void>
  detect?: () => Promise<boolean>
}

export type ModuleCategory = ModuleDefinition['category']

export interface ConfigProvider {
  id: string
  name: string
  baseUrl: string
  envKey?: string
  models?: string[]
  apiFormat?: 'chat' | 'responses'
}

export interface RelayConfig {
  provider: string
  baseUrl: string
  envKey: string
}

export interface McpServerDef {
  id: string
  name: string
  command: string
  args: string[]
  env?: Record<string, string>
}

export interface RinbakeConfig {
  providers: Record<string, ConfigProvider>
  defaultProvider?: string
  defaultModel?: string
  planModel?: string
  approvalMode?: string
}

export interface KeyEntry {
  name: string
  value: string
}
