/**
 * How much of a module's blast radius is machine-wide vs per-user.
 *
 * - `system`: writes outside any user home (apt, /etc, systemd, /opt). Affects
 *   every account on the box, so it needs root and should be run deliberately.
 * - `user`: only ever touches the invoking user's home and their own npm/pip
 *   prefixes. Must never be run as root, or it leaves root-owned dotfiles.
 * - `mixed`: both, within one module. Individual steps declare which they need.
 */
export type ModuleScope = 'system' | 'mixed' | 'user'

export interface ModuleDefinition {
  id: string
  label: string
  description: string
  category: 'system' | 'agent' | 'mcp' | 'other'
  /** Machine-wide vs per-user. Defaults to `user` when a module omits it. */
  scope: ModuleScope
  enabled: boolean
  install: () => Promise<void>
  update?: () => Promise<void>
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
