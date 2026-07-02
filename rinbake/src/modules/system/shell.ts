import { $ } from 'bun'
import { hasCommand, aptInstall } from '../../utils'
import { logStep, logInfo, input, confirm } from '../../utils/ui'

export const id = 'shell'
export const label = 'Shell (fish + proxy)'
export const description = '安装 fish shell 并配置 proxy_on/off/status 函数'
export const category = 'system' as const
export const enabled = true

export async function install(): Promise<void> {
  if (await hasCommand('fish')) {
    logStep('fish shell 已安装，跳过')
  } else {
    logStep('安装 fish shell...')
    await aptInstall('fish')
  }

  const setDefault = await confirm({ message: '设置 fish 为默认 shell？' })
  if (setDefault === true) {
    const result = await $`chsh -s $(which fish)`.nothrow()
    if (result.exitCode !== 0) {
      logStep('chsh 失败 — fish 可能不在 /etc/shells 中，稍后手动设置')
    }
  }

  const proxyAddr = await input({
    message: '代理地址',
    defaultValue: 'http://127.0.0.1:7890',
  })
  const proxy = typeof proxyAddr === 'string' ? proxyAddr : 'http://127.0.0.1:7890'

  const home = process.env.HOME || '/root'
  const fishFuncDir = `${home}/.config/fish/functions`
  await Bun.$`mkdir -p ${fishFuncDir}`.nothrow()

  await Bun.write(
    `${fishFuncDir}/proxy_on.fish`,
    `function proxy_on
    set -gx http_proxy ${proxy}
    set -gx https_proxy ${proxy}
    set -gx all_proxy ${proxy}
    echo "Proxy ON: ${proxy}"
end\n`
  )

  await Bun.write(
    `${fishFuncDir}/proxy_off.fish`,
    `function proxy_off
    set -e http_proxy
    set -e https_proxy
    set -e all_proxy
    echo "Proxy OFF"
end\n`
  )

  await Bun.write(
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
    await Bun.write(bashrcPath, bashrcText + '\n' + bashProxy + '\n')
  }

  logInfo('shell: 完成')
}

export async function detect(): Promise<boolean> {
  return hasCommand('fish')
}
