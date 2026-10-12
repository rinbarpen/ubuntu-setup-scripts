/**
 * Disable the attribution header only for DeepSeek's direct Anthropic endpoint.
 * Model IDs (including subagent IDs) do not identify the active endpoint.
 */
export function applyClaudeAttribution(env: Record<string, unknown>): void {
  let isDirectDeepSeek = false
  try {
    if (typeof env.ANTHROPIC_BASE_URL === 'string') {
      const url = new URL(env.ANTHROPIC_BASE_URL)
      isDirectDeepSeek = url.origin === 'https://api.deepseek.com'
        && (url.pathname === '/anthropic' || url.pathname === '/anthropic/')
        && !url.username && !url.password && !url.search && !url.hash
    }
  } catch {}

  if (isDirectDeepSeek) {
    env.CLAUDE_CODE_ATTRIBUTION_HEADER = '0'
  } else {
    delete env.CLAUDE_CODE_ATTRIBUTION_HEADER
  }
}
