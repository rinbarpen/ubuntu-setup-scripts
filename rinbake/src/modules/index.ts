import type { ModuleDefinition } from '../types'

import * as ubuntuBase from './system/ubuntu-base'
import * as languages from './system/languages'
import * as shell from './system/shell'
import * as fisher from './system/fisher'
import * as git from './system/git'
import * as opencode from './agents/opencode'
import * as claudeCode from './agents/claude-code'
import * as codex from './agents/codex'
import * as hermesAgent from './agents/hermes-agent'
import * as openclaw from './agents/openclaw'
import * as paseo from './agents/paseo'
import * as relay from './relay'
import * as zerotier from './zerotier'
import * as zellij from './zellij'
import * as browsers from './browsers'
import * as vms from './vms'
import * as skills from './skills'

interface ModuleExports {
  id: string
  label: string
  description: string
  category: 'system' | 'agent' | 'mcp' | 'other'
  enabled: boolean
  install: () => Promise<void>
  configure?: () => Promise<void>
  detect?: () => Promise<boolean>
}

const modules: ModuleExports[] = [
  ubuntuBase, languages, shell, fisher, git,
  opencode, claudeCode, codex, hermesAgent, openclaw, paseo,
  relay, zerotier, zellij, browsers, vms, skills,
]

export function getAllModules(): ModuleDefinition[] {
  return modules.map(m => ({
    id: m.id,
    label: m.label,
    description: m.description,
    category: m.category,
    enabled: m.enabled,
    install: m.install,
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
