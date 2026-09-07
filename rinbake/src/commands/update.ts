import color from 'picocolors'
import { intro, outro, logInfo, logWarn, select, isCancelled } from '../utils/ui'
import { getAllModules, getModule } from '../modules'

const UPDATE_ALIASES: Record<string, string> = {
  claude: 'claude-code',
  'claude-code': 'claude-code',
  codex: 'codex',
}

/** Update installed modules without re-running their interactive setup. */
export async function cmdUpdate(args: string[]): Promise<void> {
  intro(color.bgCyan(' rinbake update '))
  const updateable = getAllModules().filter(mod => mod.update)
  let ids: string[]

  if (args.includes('--all')) {
    ids = updateable.map(mod => mod.id)
  } else if (args.length > 0) {
    ids = args.map(id => UPDATE_ALIASES[id] || id)
  } else {
    const choice = await select({
      message: '选择要更新的工具',
      options: updateable.map(mod => ({ value: mod.id, label: mod.label, hint: mod.description })),
    })
    if (isCancelled(choice)) {
      outro('已取消')
      return
    }
    ids = typeof choice === 'string' ? [choice] : []
  }

  let successCount = 0
  let failCount = 0
  for (const id of ids) {
    const mod = getModule(id)
    if (!mod || !mod.update) {
      logWarn(`不可更新或未知模块: ${id}`)
      failCount++
      continue
    }
    logInfo(`更新 ${mod.label}...`)
    try {
      await mod.update()
      successCount++
    } catch (err) {
      logWarn(`${id}: 失败 — ${err}`)
      failCount++
    }
  }

  outro(color.bold(`${successCount} 成功` + (failCount > 0 ? `, ${failCount} 失败` : '')))
}
