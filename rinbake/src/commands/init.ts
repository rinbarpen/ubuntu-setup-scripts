import color from 'picocolors'
import { intro, outro, multiselect, logInfo, logWarn, isCancelled } from '../utils/ui'
import { sudoCheck } from '../utils/sudo'
import { getAllModules, getModule } from '../modules'
import { markInstalled, readInstalled } from '../config/manager'
import type { ModuleDefinition } from '../types'

export async function cmdInit(): Promise<void> {
  intro(color.bgCyan(' rinbake init '))

  await sudoCheck()

  const allModules = getAllModules()
  const installed = await readInstalled()

  const options = allModules.map(m => ({
    value: m.id,
    label: m.label,
    hint: m.description,
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

  let successCount = 0
  let failCount = 0

  for (const mod of selectedModules) {
    logInfo(`[${mod.category}] ${mod.label}`)
    try {
      await mod.install()
      await markInstalled(mod.id)
      successCount++
    } catch (err) {
      logWarn(`${mod.id}: 失败 — ${err}`)
      failCount++
    }
  }

  outro(color.bold(`完成: ${successCount} 成功` + (failCount > 0 ? `, ${failCount} 失败` : '')))
}
