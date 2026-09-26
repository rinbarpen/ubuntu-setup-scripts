import { logInfo, logWarn } from './ui'
import { isElevated, resolveIdentity, scopeNeedsSudo } from './identity'
import type { ModuleDefinition } from '../types'

const SCOPE_TAG = {
  system: '[系统]',
  mixed: '[混合]',
  user: '[用户]',
} as const

export function describeScope(mod: Pick<ModuleDefinition, 'scope'>): string {
  return SCOPE_TAG[mod.scope] ?? SCOPE_TAG.user
}

export function scopeHint(mod: ModuleDefinition): string {
  return mod.scope === 'user'
    ? `${mod.description} · ${SCOPE_TAG.user}`
    : `${mod.description} · ${SCOPE_TAG[mod.scope]} 需 sudo，影响本机所有用户`
}

/**
 * Escalate to root only once the module set is known, and only if it contains
 * something machine-wide. Asking before the user has chosen anything prompts
 * for a password that a user-scope-only run never needs.
 */
export async function ensurePrivilege(mods: ModuleDefinition[]): Promise<void> {
  const machine = mods.filter(m => scopeNeedsSudo(m.scope))
  const perUser = mods.filter(m => !scopeNeedsSudo(m.scope))

  if (perUser.length > 0) {
    const id = resolveIdentity()
    if (id.viaSudo) {
      logInfo(`以 root 运行，用户级配置将写入 ${id.user} 的家目录 (${id.home})`)
    } else if (id.elevated) {
      logWarn(`以 root 运行，用户级配置将写入 ${id.home}；如需配置其他账号请用 sudo -u <用户> rinbake ...`)
    }
  }

  if (machine.length === 0) {
    logInfo('所选模块均为用户级，无需 sudo')
    return
  }
  logInfo(`以下模块需要 root: ${machine.map(m => m.id).join(', ')}`)
  const { sudoCheck } = await import('./sudo')
  await sudoCheck()
}

/**
 * Last line of defence before a user-scope module runs. Under sudo the module
 * body itself may still shell out without dropping privileges, so say so loudly
 * rather than silently creating root-owned dotfiles.
 */
export function warnIfElevatedUserScope(mod: ModuleDefinition): void {
  if (mod.scope !== 'user' || !isElevated()) return
  const id = resolveIdentity()
  logWarn(
    `${mod.id} 是用户级模块但当前以 root 运行；若在 ${id.home} 产生 root 属主文件，` +
    `请改用 sudo -u ${id.user} -H rinbake ... 重跑`,
  )
}

export interface RunResult {
  success: number
  failed: number
}

/** Run modules in order, recording each success and keeping going on failure. */
export async function runModules(
  mods: ModuleDefinition[],
  markInstalled: (id: string) => Promise<void>,
): Promise<RunResult> {
  let success = 0
  let failed = 0
  for (const mod of mods) {
    warnIfElevatedUserScope(mod)
    logInfo(`[${mod.category}] ${mod.label} ${describeScope(mod)}`)
    try {
      await mod.install()
      await markInstalled(mod.id)
      success++
    } catch (err) {
      logWarn(`${mod.id}: 失败 — ${err}`)
      failed++
    }
  }
  return { success, failed }
}
