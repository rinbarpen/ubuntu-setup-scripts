import color from 'picocolors'
import { intro, outro, select, input, logInfo, logWarn, isCancelled } from '../utils/ui'
import { listKeys, setKey, getKey } from '../config/keys'

export async function cmdKeys(args: string[]): Promise<void> {
  if (args[0] === 'list' || (args.length === 0)) {
    await listKeysCmd()
  } else if (args[0] === 'set' && args[1]) {
    await setKeyCmd(args[1])
  } else {
    await keysInteractive()
  }
}

async function listKeysCmd(): Promise<void> {
  intro(color.bgCyan(' rinbake keys list '))
  const keys = await listKeys()
  if (keys.length === 0) {
    logInfo('尚未配置任何 API keys')
  } else {
    for (const k of keys) {
      const masked = k.value.length > 8
        ? `${k.value.slice(0, 4)}...${k.value.slice(-4)}`
        : '****'
      logInfo(`${k.name}: ${masked}`)
    }
  }
  outro(`${keys.length} 个 keys`)
}

async function setKeyCmd(name: string): Promise<void> {
  intro(color.bgCyan(` rinbake keys set ${name} `))
  const existing = await getKey(name)
  if (existing) logInfo(`当前: ${existing.slice(0, 4)}...${existing.slice(-4)}`)

  const val = await input({ message: `输入 ${name} 的值` })
  if (typeof val === 'string' && val.trim()) {
    await setKey(name, val.trim())
    logInfo(`${name} 已保存`)
  } else {
    logWarn('跳过')
  }
  outro('完成')
}

async function keysInteractive(): Promise<void> {
  intro(color.bgCyan(' rinbake keys '))

  const action = await select({
    message: 'API Key 管理',
    options: [
      { value: 'list', label: '列出所有 keys' },
      { value: 'set', label: '设置一个 key' },
    ],
  })

  if (isCancelled(action)) {
    outro('已取消')
    return
  }

  if (action === 'list') {
    await listKeysCmd()
  } else {
    const name = await input({ message: '输入环境变量名称 (如 BRAVE_API_KEY)' })
    if (typeof name === 'string' && name.trim()) {
      await setKeyCmd(name.trim())
    }
  }
}
