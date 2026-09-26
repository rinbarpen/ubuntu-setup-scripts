import color from 'picocolors'
import { intro, outro, multiselect, logInfo, isCancelled } from '../utils/ui'
import { ensurePrivilege, runModules, scopeHint } from '../utils/runner'
import { getAllModules, getModule } from '../modules'
import { markInstalled, readInstalled } from '../config/manager'
import type { ModuleDefinition } from '../types'

export async function cmdInit(): Promise<void> {
  intro(color.bgCyan(' rinbake init '))

  const allModules = getAllModules()
  const installed = await readInstalled()

  const options = allModules.map(m => ({
    value: m.id,
    label: m.label,
    // Scope is shown up front so the machine-wide blast radius is a decision,
    // not something discovered afterwards when /etc has already changed.
    hint: scopeHint(m),
    checked: installed.includes(m.id) ? true : m.enabled,
  }))

  const result = await multiselect({
    message: '选择要安装的模块（Space 切换, Enter 确认）',
    options,
  })

  if (isCancelled(result)) {
    outro('已取消')
    return
  }

  const selectedIds = result.filter((v): v is string => typeof v === 'string')
  if (selectedIds.length === 0) {
    outro('未选择任何模块')
    return
  }

  // Sort by category order: system -> agent -> other
  const categoryOrder: Record<string, number> = { system: 0, agent: 1, other: 2, mcp: 3 }
  const selectedModules = selectedIds
    .map(id => getModule(id))
    .filter((m): m is ModuleDefinition => m !== undefined)
    .sort((a, b) => (categoryOrder[a.category] ?? 99) - (categoryOrder[b.category] ?? 99))

  // Escalate only once the selection is known, and only if it needs root.
  await ensurePrivilege(selectedModules)

  const { success, failed } = await runModules(selectedModules, markInstalled)

  outro(color.bold(`完成: ${success} 成功` + (failed > 0 ? `, ${failed} 失败` : '')))
}
