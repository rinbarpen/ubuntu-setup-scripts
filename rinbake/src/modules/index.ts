import type { ModuleDefinition, ModuleScope } from '../types'
import { scopeNeedsSudo } from '../utils/identity'

import * as ubuntuBase from './system/ubuntu-base'
import * as languages from './system/languages'
import * as shell from './system/shell'
import * as fisher from './system/fisher'
import * as git from './system/git'
import * as githubCli from './system/github-cli'
import * as opencode from './agents/opencode'
import * as claudeCode from './agents/claude-code'
import * as codex from './agents/codex'
import * as hermesAgent from './agents/hermes-agent'
import * as openclaw from './agents/openclaw'
import * as paseo from './agents/paseo'
import * as orca from './agents/orca'
import * as pi from './agents/pi'
import * as omp from './agents/omp'
import * as zerotier from './zerotier'
import * as zellij from './zellij'
import * as browsers from './browsers'
import * as vms from './vms'
import * as skills from './skills'
import * as aris from './aris'
import * as dockerConfig from './docker-config'
import * as firecrawl from './firecrawl'
import * as overleaf from './overleaf'
import * as omniroute from './omniroute'

interface ModuleExports {
  id: string
  label: string
  description: string
  category: 'system' | 'agent' | 'mcp' | 'other'
  scope: ModuleScope
  enabled: boolean
  install: () => Promise<void>
  update?: () => Promise<void>
  configure?: () => Promise<void>
  detect?: () => Promise<boolean>
}

const modules: ModuleExports[] = [
  ubuntuBase, languages, shell, fisher, git, githubCli,
  opencode, claudeCode, codex, hermesAgent, openclaw, paseo, orca, pi, omp,
  zerotier, zellij, browsers, vms, skills,
  aris, dockerConfig, firecrawl, overleaf,
  omniroute,
]

export function getAllModules(): ModuleDefinition[] {
  return modules.map(m => ({
    id: m.id,
    label: m.label,
    description: m.description,
    category: m.category,
    scope: m.scope,
    enabled: m.enabled,
    install: m.install,
    update: m.update,
    configure: m.configure,
    detect: m.detect,
  }))
}

export function getModule(id: string): ModuleDefinition | undefined {
  return getAllModules().find(m => m.id === id)
}

export function getModulesByCategory(category: string): ModuleDefinition[] {
  return getAllModules().filter(m => m.category === category)
}

/**
 * Group modules into the two buckets a multi-user machine cares about: changes
 * every account on the box will see, and changes confined to one home directory.
 */
export function partitionByScope(mods: ModuleDefinition[]): {
  machine: ModuleDefinition[]
  perUser: ModuleDefinition[]
} {
  const machine: ModuleDefinition[] = []
  const perUser: ModuleDefinition[] = []
  for (const m of mods) (scopeNeedsSudo(m.scope) ? machine : perUser).push(m)
  return { machine, perUser }
}
