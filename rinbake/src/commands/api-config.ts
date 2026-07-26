import color from 'picocolors'
import { intro, outro, multiselect, logInfo, logWarn } from '../utils/ui'
import { promptAndSetKey } from '../config/keys'

const KEY_DEFS: { name: string; label: string; secret: boolean }[] = [
  { name: 'BRAVE_API_KEY',      label: 'Brave Search API key',                      secret: true },
  { name: 'GITHUB_TOKEN',       label: 'GitHub Personal Access Token',               secret: true },
  { name: 'OPENAI_API_KEY',     label: 'OpenAI API key',                             secret: true },
  { name: 'ANTHROPIC_API_KEY',  label: 'Anthropic API key',                          secret: true },
  { name: 'DEEPSEEK_API_KEY',   label: 'DeepSeek API key',                           secret: true },
  { name: 'POSTGRES_DSN',       label: 'PostgreSQL connection string (DSN)',         secret: false },
  { name: 'ZEROTIER_NETWORK_ID',label: 'ZeroTier network ID',                        secret: false },
  { name: 'PROXY_ADDR',         label: 'HTTP proxy address (e.g. http://127.0.0.1:7890)', secret: false },
]

export async function cmdApiConfig(args: string[]): Promise<void> {
  intro(color.bgCyan(' rinbake api-config '))

  if (args[0] === '--list' || args[0] === '-l') {
    const { listKeys } = await import('../config/keys')
    const keys = await listKeys()
    if (keys.length === 0) { logInfo('No API keys configured yet.'); outro(''); return }
    logInfo(`Configured API keys:`)
    for (const k of keys) {
      const masked = k.value.length > 8 ? `${k.value.slice(0, 4)}...${k.value.slice(-4)}` : '****'
      console.log(`  ${k.name.padEnd(25)} ${masked}`)
    }
    outro('')
    return
  }

  if (args[0] === '--show' || args[0] === '-s') {
    const { listKeys } = await import('../config/keys')
    const keys = await listKeys()
    if (keys.length === 0) { logInfo('No API keys configured yet.'); outro(''); return }
    logInfo(`API keys:`)
    for (const k of keys) {
      console.log(`  ${k.name}=${k.value}`)
    }
    outro('')
    return
  }

  if (args[0] === '--set' && args[1] && args[2]) {
    const { setKey } = await import('../config/keys')
    await setKey(args[1], args[2])
    logInfo(`${args[1]} saved`)
    outro('')
    return
  }

  const choices = await multiselect({
    message: '选择要配置的 API Key (Space 切换, Enter 确认)',
    options: KEY_DEFS.map(k => ({ value: k.name, label: k.label, hint: '', checked: true })),
    required: false,
  })

  if (!Array.isArray(choices)) { outro('已取消'); return }

  for (const name of choices) {
    if (typeof name !== 'string') continue
    const def = KEY_DEFS.find(k => k.name === name)
    if (def) await promptAndSetKey(def.name, def.label)
  }

  const { listKeys } = await import('../config/keys')
  logInfo('API configuration complete')
  const keys = await listKeys()
  for (const k of keys) {
    const masked = k.value.length > 8 ? `${k.value.slice(0, 4)}...${k.value.slice(-4)}` : '****'
    console.log(`  ${k.name.padEnd(25)} ${masked}`)
  }
  outro('完成')
}
