import color from 'picocolors'
import { intro, outro, select, logInfo, logWarn, isCancelled } from '../utils/ui'
import { sudoCheck } from '../utils/sudo'
import { getAllModules, getModule } from '../modules'
import { markInstalled, readInstalled } from '../config/manager'

export async function cmdInstall(args: string[]): Promise<void> {
  intro(color.bgCyan(' rinbake install '))

  if (args.length > 0) {
    // Install specific modules
    await sudoCheck()
    let successCount = 0
    let failCount = 0
    for (const id of args) {
      const mod = getModule(id)
      if (!mod) {
        logWarn(`未知模块: ${id}`)
        failCount++
        continue
      }
      logInfo(`安装 ${mod.label}...`)
      try {
        await mod.install()
        await markInstalled(mod.id)
        successCount++
      } catch (err) {
        logWarn(`${id}: 失败 — ${err}`)
        failCount++
      }
    }
    outro(color.bold(`${successCount} 成功` + (failCount > 0 ? `, ${failCount} 失败` : '')))
    return
  }

  // Interactive selection
  await sudoCheck()
  const installed = await readInstalled()
  const allModules = getAllModules()

  const options = allModules.map(m => ({
    value: m.id,
    label: m.label,
    hint: m.description,
  }))

  const choices = await select({
    message: '选择要安装的模块',
    options: [
      { value: '__all__', label: '全部安装', hint: '安装所有模块' },
      ...options.map(o => ({ value: o.value, label: o.label, hint: o.hint })),
    ],
  })

  if (isCancelled(choices)) {
    outro('已取消')
    return
  }

  const ids = choices === '__all__'
    ? allModules.map(m => m.id)
    : [choices]

  let successCount = 0
  let failCount = 0
  for (const id of ids) {
    if (typeof id !== 'string') continue
    const mod = getModule(id)
    if (!mod) { logWarn(`未知: ${id}`); continue }
    logInfo(`安装 ${mod.label}...`)
    try {
      await mod.install()
      await markInstalled(mod.id)
      successCount++
    } catch (err) {
      logWarn(`${id}: 失败 — ${err}`)
      failCount++
    }
  }

  outro(color.bold(`${successCount} 成功` + (failCount > 0 ? `, ${failCount} 失败` : '')))
}
