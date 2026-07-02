import color from 'picocolors'
import { intro, outro, logInfo } from '../utils/ui'
import { hasCommand } from '../utils/shell'
import { getAllModules } from '../modules'
import { listKeys } from '../config/keys'

export async function cmdStatus(): Promise<void> {
  intro(color.bgCyan(' rinbake status '))

  const allModules = getAllModules()
  let foundCount = 0

  for (const mod of allModules) {
    const detected = mod.detect ? await mod.detect() : false
    const symbol = detected ? color.green('✓') : color.dim('✗')
    logInfo(`  ${symbol} ${mod.label}`)
    if (detected) foundCount++
  }

  const keys = await listKeys()
  logInfo('')
  logInfo(`API Keys: ${keys.length} 个已配置`)
  for (const k of keys) {
    const masked = k.value.length > 8
      ? `${k.value.slice(0, 4)}...${k.value.slice(-4)}`
      : '****'
    logInfo(`  ${k.name}: ${masked}`)
  }

  outro(color.bold(`${foundCount}/${allModules.length} 已安装`))
}
