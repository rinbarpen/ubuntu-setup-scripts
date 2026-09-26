import color from 'picocolors'
import { intro, logInfo, logWarn, outro } from '../utils/ui'
import {
  configure,
  configureClient,
  doctor,
  listProviderPresets,
  openDashboard,
  restartService,
  showLogs,
  startService,
  status,
  stopService,
} from '../modules/omniroute'
import type { OmniRouteClient } from '../config/omniroute'

const CLIENTS = new Set<OmniRouteClient>(['codex', 'claude-code', 'opencode'])

export async function cmdOmniRoute(args: string[]): Promise<void> {
  const action = args[0] || 'status'
  intro(color.bgCyan(` rinbake omniroute ${action} `))

  switch (action) {
    case 'start':
      await startService()
      break
    case 'stop':
      await stopService()
      break
    case 'restart':
      await restartService()
      break
    case 'status':
      await status()
      break
    case 'doctor':
      if ((await doctor()) !== 0) {
        logWarn('OmniRoute doctor 返回非零状态')
        process.exitCode = 1
      }
      break
    case 'logs':
      await showLogs()
      break
    case 'dashboard':
      await openDashboard()
      break
    case 'providers':
      listProviderPresets()
      logInfo('使用 Dashboard → Providers 连接真实 Provider')
      break
    case 'configure': {
      const target = args[1]
      if (target && CLIENTS.has(target as OmniRouteClient)) {
        await configureClient(target as OmniRouteClient)
      } else if (target) {
        logWarn(`未知客户端: ${target}；支持 codex、claude-code、opencode`)
      } else {
        await configure()
      }
      break
    }
    default:
      logWarn(`未知操作: ${action}`)
      logInfo('用法: start | stop | restart | status | doctor | logs | dashboard | providers | configure [client]')
  }

  outro('完成')
}
