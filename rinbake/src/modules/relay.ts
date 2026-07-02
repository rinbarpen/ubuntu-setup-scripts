import { logStep, logInfo, select, input } from '../utils/ui'
import { promptAndSetKey } from '../config/keys'
import { readConfig, writeConfig } from '../config/manager'

export const id = 'relay'
export const label = 'Relay / 中转代理配置'
export const description = '配置 OpenRouter / AIHubMix 中转代理'
export const category = 'other' as const
export const enabled = true

export async function install(): Promise<void> {
  await configure()
}

export async function configure(): Promise<void> {
  const config = await readConfig()

  const providerType = await select({
    message: '选择中转代理服务',
    options: [
      { value: 'openrouter', label: 'OpenRouter', hint: 'https://openrouter.ai/api/v1' },
      { value: 'aihubmix', label: 'AIHubMix', hint: 'https://aihubmix.com/v1' },
      { value: 'custom', label: '自定义中转' },
    ],
  })

  if (typeof providerType !== 'string') return

  let baseUrl = ''
  let envKey = ''

  switch (providerType) {
    case 'openrouter':
      baseUrl = 'https://openrouter.ai/api/v1'
      envKey = 'OPENROUTER_API_KEY'
      break
    case 'aihubmix':
      baseUrl = 'https://aihubmix.com/v1'
      envKey = 'AIHUBMIX_API_KEY'
      break
    case 'custom': {
      const url = await input({ message: '中转 base URL' })
      if (typeof url === 'string' && url.trim()) baseUrl = url.trim()
      const kn = await input({ message: 'API Key 环境变量名' })
      if (typeof kn === 'string' && kn.trim()) envKey = kn.trim()
      break
    }
  }

  if (envKey) {
    await promptAndSetKey(envKey, `${envKey} (中转 API Key)`)
  }

  config.defaultProvider = providerType
  config.providers[providerType] = {
    id: providerType,
    name: providerType.charAt(0).toUpperCase() + providerType.slice(1),
    baseUrl,
    envKey: envKey || undefined,
  }

  await writeConfig(config)
  logInfo(`中转代理配置完成: ${baseUrl}`)
}

export async function detect(): Promise<boolean> {
  const config = await readConfig()
  return !!config.defaultProvider
}
