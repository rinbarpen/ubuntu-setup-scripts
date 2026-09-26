import color from 'picocolors'
import { intro, outro, select, logWarn, isCancelled } from '../utils/ui'
import { ensurePrivilege, runModules, scopeHint } from '../utils/runner'
import { getAllModules, getModule } from '../modules'
import { markInstalled, readInstalled } from '../config/manager'
import type { ModuleDefinition } from '../types'

function finish(success: number, failed: number): void {
  outro(color.bold(`${success} 成功` + (failed > 0 ? `, ${failed} 失败` : '')))
}

export async function cmdInstall(args: string[]): Promise<void> {
  intro(color.bgCyan(' rinbake install '))

  if (args.length > 0) {
    const requested: ModuleDefinition[] = []
    let unknown = 0
    for (const id of args) {
      const mod = getModule(id)
      if (!mod) {
        logWarn(`未知模块: ${id}`)
        unknown++
        continue
      }
      requested.push(mod)
    }
    if (requested.length === 0) {
      finish(0, unknown)
      return
    }
    await ensurePrivilege(requested)
    const { success, failed } = await runModules(requested, markInstalled)
    finish(success, failed + unknown)
    return
  }

  // Interactive selection
  const installed = await readInstalled()
  const allModules = getAllModules()

  const choices = await select({
    message: '选择要安装的模块',
    options: [
      { value: '__all__', label: '全部安装', hint: '安装所有模块（含系统级，需要 sudo）' },
      ...allModules.map(o => ({ value: o.id, label: o.label, hint: scopeHint(o) })),
    ],
  })

  if (isCancelled(choices)) {
    outro('已取消')
    return
  }

  const ids = choices === '__all__' ? allModules.map(m => m.id) : [choices]

  const selected: ModuleDefinition[] = []
  for (const id of ids) {
    if (typeof id !== 'string') continue
    const mod = getModule(id)
    if (!mod) {
      logWarn(`未知: ${id}`)
      continue
    }
    selected.push(mod)
  }

  await ensurePrivilege(selected)
  const { success, failed } = await runModules(selected, markInstalled)
  finish(success, failed)
}
