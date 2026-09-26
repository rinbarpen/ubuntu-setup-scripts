export const OMNIROUTE_PACKAGE = 'omniroute'
export const OMNIROUTE_DEFAULT_PORT = 20128
export const OMNIROUTE_DEFAULT_HOST = 'localhost'
export const OMNIROUTE_API_KEY = 'OMNIROUTE_API_KEY'
export const OMNIROUTE_DEFAULT_MODEL = 'auto'

export type OmniRouteAuth = 'api-key' | 'oauth' | 'cookie' | 'none'
export type OmniRouteProtocol = 'openai' | 'anthropic' | 'web' | 'custom'

export interface OmniRouteProviderPreset {
  id: string
  label: string
  protocol: OmniRouteProtocol
  auth: OmniRouteAuth
  modelHint: string
  manualAuth: boolean
}

export const OMNIROUTE_PROVIDER_PRESETS: OmniRouteProviderPreset[] = [
  { id: 'openai', label: 'OpenAI', protocol: 'openai', auth: 'api-key', modelHint: 'gpt-*', manualAuth: false },
  { id: 'anthropic', label: 'Anthropic', protocol: 'anthropic', auth: 'api-key', modelHint: 'claude-*', manualAuth: false },
  { id: 'deepseek', label: 'DeepSeek', protocol: 'openai', auth: 'api-key', modelHint: 'deepseek-*', manualAuth: false },
  { id: 'openrouter', label: 'OpenRouter', protocol: 'openai', auth: 'api-key', modelHint: 'provider/model', manualAuth: false },
  { id: 'gemini', label: 'Google Gemini', protocol: 'openai', auth: 'api-key', modelHint: 'gemini-*', manualAuth: false },
  { id: 'chatgpt-web', label: 'ChatGPT Web / GPT-Web', protocol: 'web', auth: 'cookie', modelHint: 'auto or provider/model', manualAuth: true },
  { id: 'claude-web', label: 'Claude Web', protocol: 'web', auth: 'cookie', modelHint: 'auto or provider/model', manualAuth: true },
  { id: 'custom', label: '自定义 Provider', protocol: 'custom', auth: 'api-key', modelHint: '自定义', manualAuth: false },
]

export type OmniRouteClient = 'codex' | 'claude-code' | 'opencode'

export const OMNIROUTE_CLIENTS: Record<OmniRouteClient, {
  label: string
  endpoint: string
  protocol: 'openai-responses' | 'anthropic' | 'openai-compatible'
}> = {
  codex: {
    label: 'Codex',
    endpoint: '/v1',
    protocol: 'openai-responses',
  },
  'claude-code': {
    label: 'Claude Code',
    endpoint: '/',
    protocol: 'anthropic',
  },
  opencode: {
    label: 'OpenCode',
    endpoint: '/v1',
    protocol: 'openai-compatible',
  },
}

export function getOmniRouteBaseUrl(port = OMNIROUTE_DEFAULT_PORT): string {
  return `http://${OMNIROUTE_DEFAULT_HOST}:${port}`
}

export function getOmniRouteClientUrl(client: OmniRouteClient, port = OMNIROUTE_DEFAULT_PORT): string {
  const base = getOmniRouteBaseUrl(port)
  return client === 'claude-code' ? base : `${base}/v1`
}

export function getOmniRouteProvider(port = OMNIROUTE_DEFAULT_PORT): {
  id: string
  name: string
  baseUrl: string
  envKey: string
  apiFormat: 'chat' | 'responses'
} {
  return {
    id: 'omniroute',
    name: 'OmniRoute',
    baseUrl: getOmniRouteBaseUrl(port) + '/v1',
    envKey: OMNIROUTE_API_KEY,
    apiFormat: 'responses',
  }
}

export function getProviderPreset(id: string): OmniRouteProviderPreset | undefined {
  return OMNIROUTE_PROVIDER_PRESETS.find(provider => provider.id === id)
}
