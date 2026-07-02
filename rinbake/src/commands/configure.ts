import color from 'picocolors'
import { intro, outro, select, logWarn, isCancelled, logInfo } from '../utils/ui'
import { getAllModules, getModule } from '../modules'

export async function cmdConfigure(args: string[]): Promise<void> {
  intro(color.bgCyan(' rinbake configure '))

  if (args.length > 0) {
    for (const id of args) {
      const mod = getModule(id)
      if (!mod) {
        logWarn(`未知模块: ${id}`)
        continue
      }
      if (mod.configure) {
        logInfo(`配置 ${mod.label}...`)
        await mod.configure()
      } else {
        logWarn(`${mod.id}: 无可配置选项`)
      }
    }
    outro('配置完成')
    return
  }

  const allModules = getAllModules().filter(m => m.configure)

  const choice = await select({
    message: '选择要配置的模块',
    options: [
      { value: '__all__', label: '全部配置' },
      ...allModules.map(m => ({ value: m.id, label: m.label, hint: m.description })),
    ],
  })

  if (isCancelled(choice)) {
    outro('已取消')
    return
  }

  const ids = choice === '__all__'
    ? allModules.map(m => m.id)
    : [choice]

  for (const id of ids) {
    if (typeof id !== 'string') continue
    const mod = getModule(id)
    if (!mod || !mod.configure) continue
    logInfo(`配置 ${mod.label}...`)
    await mod.configure()
  }

  outro('配置完成')
}
