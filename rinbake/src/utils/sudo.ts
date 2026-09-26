import { $ } from 'bun'
import { logInfo, logWarn } from './ui'

export async function sudoCheck(): Promise<void> {
  logInfo('检查 sudo 权限...')
  const result = await $`sudo -v`.nothrow()
  if (result.exitCode !== 0) {
    logWarn('无法获取 sudo 权限，部分操作可能失败')
    return
  }
  keepAlive()
}

function keepAlive(): void {
  // unref: the timer must never be the reason the process refuses to exit
  const timer = setInterval(() => {
    $`sudo -v`.nothrow()
  }, 30000)
  timer.unref?.()
}

export async function sudoRun(cmdStr: string): Promise<{ exitCode: number; stdout: string; stderr: string }> {
  const result = await $`sudo sh -c ${cmdStr}`.nothrow()
  return {
    exitCode: result.exitCode,
    stdout: result.stdout.toString().trim(),
    stderr: result.stderr.toString().trim(),
  }
}

export async function aptInstall(...packages: string[]): Promise<boolean> {
  logInfo(`安装: ${packages.join(', ')}`)
  // ${packages} spreads into separate argv entries; joining would pass one
  // bogus "curl wget git" argument and apt would report nothing installed.
  const result = await $`sudo apt-get install -y ${packages}`.nothrow()
  return result.exitCode === 0
}
