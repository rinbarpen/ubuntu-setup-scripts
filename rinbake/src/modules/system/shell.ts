import { $ } from 'bun'
import { aptInstall, hasCommand, targetHome, targetUser, writeAsUser } from '../../utils'
import { logStep, logInfo, logWarn, input, confirm, isInteractive } from '../../utils/ui'

export const id = 'shell'
export const label = 'Shell (fish + proxy)'
export const description = '安装 fish shell 并配置 proxy_on/off/status 函数'
export const category = 'system' as const
export const scope = 'mixed' as const
export const enabled = true

/** The account's login shell, straight from the passwd database. */
async function currentShell(user: string): Promise<string> {
  const r = await $`getent passwd ${user}`.quiet().nothrow()
  const parts = r.stdout.toString().trim().split(':')
  return parts.length >= 7 ? parts[6] : ''
}

/**
 * chsh refuses any shell absent from /etc/shells, which is the usual reason a
 * freshly installed fish cannot be made default. Register it first.
 */
async function ensureShellListed(shellPath: string): Promise<boolean> {
  const listed = (await Bun.file('/etc/shells').text().catch(() => ''))
    .split('\n')
    .map(l => l.trim())
  if (listed.includes(shellPath)) return true

  logStep(`${shellPath} 不在 /etc/shells 中，添加...`)
  const r = await $`printf '%s\n' ${shellPath} | sudo tee -a /etc/shells`.quiet().nothrow()
  if (r.exitCode !== 0) {
    logWarn(`写入 /etc/shells 失败 — ${r.stderr.toString().trim() || 'sudo 不可用'}`)
    return false
  }
  return true
}

/** Offer to make fish the login shell, and do it only if the user says yes. */
async function offerDefaultShell(): Promise<void> {
  // apt may have failed; do not offer to switch to a shell that is not there.
  // `command -v` is a shell builtin Bun's shell does not implement.
  const fishPath = (await $`which fish`.quiet().nothrow()).stdout.toString().trim()
  if (!fishPath) {
    logWarn('未找到 fish，跳过设置默认 shell')
    return
  }

  const user = targetUser()
  const current = await currentShell(user)
  if (current === fishPath) {
    logStep(`默认 shell 已是 ${fishPath}`)
    return
  }

  if (!isInteractive()) {
    logStep(`默认 shell 仍为 ${current || '未知'}（非交互模式，不自动更改）`)
    return
  }

  if (!(await ensureShellListed(fishPath))) {
    logWarn('fish 未注册到 /etc/shells，跳过设置默认 shell')
    return
  }

  const setDefault = await confirm({
    message: `将 ${user} 的默认 shell 从 ${current || '未知'} 改为 ${fishPath}？`,
    defaultValue: true,
  })
  if (setDefault !== true) {
    logStep(`保持默认 shell: ${current || '未知'}`)
    return
  }

  // Name the account: bare `chsh` under sudo would change root's shell.
  const result = await $`chsh -s ${fishPath} ${user}`.quiet().nothrow()
  if (result.exitCode !== 0) {
    const why = (result.stderr.toString() || result.stdout.toString()).trim().split('\n').pop() || `exit ${result.exitCode}`
    logWarn(`chsh 失败 — ${why}`)
    return
  }
  logInfo(`默认 shell 已改为 ${fishPath}（重新登录后生效）`)
}

export async function install(): Promise<void> {
  if (await hasCommand('fish')) {
    logStep('fish shell 已安装，跳过')
  } else {
    logStep('安装 fish shell...')
    await aptInstall('fish')
  }

  await offerDefaultShell()

  const proxyAddr = await input({
    message: '代理地址',
    defaultValue: 'http://127.0.0.1:7890',
  })
  const proxy = typeof proxyAddr === 'string' ? proxyAddr : 'http://127.0.0.1:7890'

  const home = targetHome()
  const fishFuncDir = `${home}/.config/fish/functions`

  await writeAsUser(
    `${fishFuncDir}/proxy_on.fish`,
    `function proxy_on
    set -gx http_proxy ${proxy}
    set -gx https_proxy ${proxy}
    set -gx all_proxy ${proxy}
    echo "Proxy ON: ${proxy}"
end\n`
  )

  await writeAsUser(
    `${fishFuncDir}/proxy_off.fish`,
    `function proxy_off
    set -e http_proxy
    set -e https_proxy
    set -e all_proxy
    echo "Proxy OFF"
end\n`
  )

  await writeAsUser(
    `${fishFuncDir}/proxy_status.fish`,
    `function proxy_status
    echo "http_proxy:  $http_proxy"
    echo "https_proxy: $https_proxy"
    echo "all_proxy:   $all_proxy"
end\n`
  )

  const bashrcPath = `${home}/.bashrc`
  const bashrcText = (await Bun.file(bashrcPath).exists()) ? await Bun.file(bashrcPath).text() : ''
  const marker = '# rinbake: shell proxy'
  if (!bashrcText.includes(marker)) {
    const bashProxy = `
${marker}
PROXY_ADDR="${proxy}"
proxy_on()     { export http_proxy=$PROXY_ADDR https_proxy=$PROXY_ADDR all_proxy=$PROXY_ADDR; echo "Proxy ON: $PROXY_ADDR"; }
proxy_off()    { unset http_proxy https_proxy all_proxy; echo "Proxy OFF"; }
proxy_status() { echo "http_proxy: $http_proxy"; echo "https_proxy: $https_proxy"; echo "all_proxy: $all_proxy"; }
`
    await writeAsUser(bashrcPath, bashrcText + '\n' + bashProxy + '\n')
  }

  logInfo('shell: 完成')
}

export async function detect(): Promise<boolean> {
  return hasCommand('fish')
}
