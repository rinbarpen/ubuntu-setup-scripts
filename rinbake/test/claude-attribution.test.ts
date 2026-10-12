import { describe, test, expect } from 'bun:test'
import { chmodSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
import { applyClaudeAttribution } from '../src/config/claude-attribution'

const HEADER = 'CLAUDE_CODE_ATTRIBUTION_HEADER'
const projectRoot = resolve(import.meta.dir, '..')
const moduleUrl = (path: string) => JSON.stringify(pathToFileURL(join(projectRoot, 'src', path)).href)

describe('Claude attribution endpoint policy', () => {
  for (const endpoint of [
    'https://api.deepseek.com/anthropic',
    'https://api.deepseek.com/anthropic/',
    'https://API.DEEPSEEK.COM:443/anthropic',
  ]) {
    test(`sets zero for direct endpoint: ${endpoint}`, () => {
      const env: Record<string, unknown> = { ANTHROPIC_BASE_URL: endpoint, [HEADER]: '1', CUSTOM: 'keep' }
      applyClaudeAttribution(env)
      expect(env[HEADER]).toBe('0')
      expect(env.CUSTOM).toBe('keep')
      applyClaudeAttribution(env)
      expect(env[HEADER]).toBe('0')
    })
  }

  for (const endpoint of [
    undefined, null, 123, '', 'not a URL',
    'http://localhost:20128', 'http://localhost:20128/',
    'https://api.anthropic.com', 'https://aixor.org',
    'https://dashscope-intl.aliyuncs.com/apps/anthropic',
    'https://api.deepseek.com.evil.test/anthropic',
    'https://deepseek-proxy.test/anthropic',
    'https://api.deepseek.com/v1', 'http://api.deepseek.com/anthropic',
    'https://api.deepseek.com:8443/anthropic',
    'https://user:password@api.deepseek.com/anthropic',
    'https://api.deepseek.com/anthropic?proxy=1',
    'https://api.deepseek.com/anthropic#proxy',
  ]) {
    test(`removes prior values for non-direct endpoint: ${endpoint}`, () => {
      for (const prior of [undefined, '0', '1']) {
        const env: Record<string, unknown> = {
          ANTHROPIC_BASE_URL: endpoint,
          ANTHROPIC_MODEL: 'deepseek-v4-pro',
          CLAUDE_CODE_SUBAGENT_MODEL: 'deepseek-v4-flash',
          CUSTOM: 'keep',
        }
        if (prior !== undefined) env[HEADER] = prior
        applyClaudeAttribution(env)
        expect(env).not.toHaveProperty(HEADER)
        expect(env.CUSTOM).toBe('keep')
        const once = JSON.stringify(env)
        applyClaudeAttribution(env)
        expect(JSON.stringify(env)).toBe(once)
      }
    })
  }
})

function fixture() {
  const home = mkdtempSync(join(tmpdir(), 'rinbake-claude-attribution-'))
  const bin = join(home, 'bin')
  const settingsPath = join(home, '.claude/settings.json')
  mkdirSync(bin)
  mkdirSync(join(home, '.claude'))
  const stub = join(bin, 'omniroute')
  writeFileSync(stub, `#!/bin/sh
[ "$1" = configure ] || exit 90
[ "\${OMNIROUTE_STUB_EXIT:-0}" = 0 ] || exit "$OMNIROUTE_STUB_EXIT"
[ "$2" = claude ] || exit 0
python3 - <<'PY'
import json, os, pathlib
path = pathlib.Path(os.environ["HOME"]) / ".claude/settings.json"
settings = json.loads(path.read_text()) if path.exists() else {}
env = settings.setdefault("env", {})
env["ANTHROPIC_BASE_URL"] = "http://localhost:20128"
env["CLAUDE_CODE_ATTRIBUTION_HEADER"] = "0"
path.write_text(json.dumps(settings) + "\\n")
PY
`)
  chmodSync(stub, 0o755)
  return {
    settingsPath,
    write(settings: unknown) { writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + '\n') },
    read() { return JSON.parse(readFileSync(settingsPath, 'utf8')) },
    readMcp() { return JSON.parse(readFileSync(join(home, '.claude.json'), 'utf8')) },
    run(code: string, extraEnv: Record<string, string> = {}) {
      const result = Bun.spawnSync([process.execPath, '-e', code], {
        cwd: projectRoot,
        env: {
          ...process.env, HOME: home, USER: 'rinbake-attribution-test', LOGNAME: 'rinbake-attribution-test',
          SUDO_USER: '', PATH: `${bin}:${process.env.PATH}`, ...extraEnv,
        },
        stdout: 'pipe', stderr: 'pipe', timeout: 10000,
      })
      expect(result.exitCode, result.stdout.toString() + result.stderr.toString()).toBe(0)
      return result
    },
    cleanup() { rmSync(home, { recursive: true, force: true }) },
  }
}

const uiMock = `
  import { mock } from 'bun:test';
  mock.module(${moduleUrl('utils/ui.ts')}, () => ({
    logInfo() {}, logWarn() {}, logError() {}, logStep() {}, intro() {}, outro() {},
    isCancelled: value => typeof value === 'symbol',
    select: async opts => opts.options[0].value,
    input: async () => 'fixture-token', password: async () => '',
    multiselect: async () => [], confirm: async () => false,
  }));
`

const preserved = {
  env: {
    ANTHROPIC_BASE_URL: 'https://api.deepseek.com/anthropic',
    ANTHROPIC_MODEL: 'deepseek-v4-pro',
    ANTHROPIC_AUTH_TOKEN: 'fixture-token',
    CLAUDE_CODE_SUBAGENT_MODEL: 'deepseek-v4-flash',
    [HEADER]: '0',
    CUSTOM: 'keep',
  },
  permissions: { defaultMode: 'acceptEdits', allow: ['Read'] },
  hooks: { Stop: [{ hooks: [{ type: 'command', command: 'echo fixture' }] }] },
  customField: { keep: true },
}

describe('Claude attribution settings writers (isolated HOME)', () => {
  test('configure clears prior values and preserves unrelated settings', () => {
    const f = fixture()
    try {
      for (const prior of ['0', '1']) {
        f.write({ ...preserved, env: { ...preserved.env, [HEADER]: prior },
          mcpServers: { fixture: { command: 'fixture-mcp' } } })
        f.run(`${uiMock}
          mock.module(${moduleUrl('modules/omniroute.ts')}, () => ({
            ensureReady: async () => {}, configureClient: async () => 0,
          }));
          const { configure } = await import(${moduleUrl('modules/agents/claude-code.ts')});
          await configure();
        `)
        const settings = f.read()
        expect(settings.env).not.toHaveProperty(HEADER)
        expect(settings.env.CUSTOM).toBe('keep')
        expect(settings.env.CLAUDE_CODE_SUBAGENT_MODEL).toBe('deepseek-v4-flash')
        expect(settings.permissions.allow).toEqual(preserved.permissions.allow)
        expect(settings.hooks).toEqual(preserved.hooks)
        expect(settings.customField).toEqual(preserved.customField)
        expect(f.readMcp().mcpServers).toEqual({ fixture: { command: 'fixture-mcp' } })
      }
    } finally { f.cleanup() }
  })

  test('update migration clears legacy header and is idempotent', () => {
    const f = fixture()
    try {
      for (const prior of ['0', '1']) {
        f.write({ ...preserved, env: { ...preserved.env, [HEADER]: prior },
          mcpServers: { fixture: { command: 'fixture-mcp' } } })
        const code = `
          const { migrateCurrentSettings } = await import(${moduleUrl('modules/agents/claude-code.ts')});
          await migrateCurrentSettings();
        `
        f.run(code)
        const settings = f.read()
        expect(settings.env.ANTHROPIC_BASE_URL).toBe('http://localhost:20128')
        expect(settings.env).not.toHaveProperty(HEADER)
        expect(settings.env.CUSTOM).toBe('keep')
        expect(settings.permissions).toEqual(preserved.permissions)
        expect(settings.hooks).toEqual(preserved.hooks)
        expect(settings.customField).toEqual(preserved.customField)
        expect(f.readMcp().mcpServers).toEqual({ fixture: { command: 'fixture-mcp' } })
        f.run(code)
        expect(f.read()).toEqual(settings)
      }
    } finally { f.cleanup() }
  })

  test('model switch adds for DeepSeek and clears for every other provider', () => {
    const f = fixture()
    try {
      const switchTo = (provider: string, model: string) => {
        f.run(`${uiMock}
          mock.module(${moduleUrl('modules/omniroute.ts')}, () => ({ ensureReady: async () => {} }));
          const { cmdModelSwitch } = await import(${moduleUrl('commands/model-switch.ts')});
          await cmdModelSwitch(['switch', ${JSON.stringify(provider)}, ${JSON.stringify(model)}]);
        `)
      }
      for (const [provider, model] of [
        ['qwen', 'qwen3.6-plus'], ['glm', 'glm-5'], ['minimax', 'MiniMax-M2.7'],
        ['aixor', 'deepseek-v4-pro'], ['omniroute', 'auto'],
      ]) {
        f.write(preserved)
        switchTo('deepseek', 'deepseek-v4-pro')
        expect(f.read().env[HEADER]).toBe('0')
        switchTo(provider, model)
        expect(f.read().env).not.toHaveProperty(HEADER)
        const settings = f.read()
        switchTo(provider, model)
        expect(f.read()).toEqual(settings)
      }
    } finally { f.cleanup() }
  })

  test('standalone OmniRoute configure cleans external CLI output and preserves settings', () => {
    const f = fixture()
    try {
      f.write({ ...preserved, mcpServers: { fixture: { command: 'fixture-mcp' } } })
      const code = `
        const { configureClient } = await import(${moduleUrl('modules/omniroute.ts')});
        if (await configureClient('claude-code') !== 0) process.exit(1);
      `
      f.run(code)
      const settings = f.read()
      expect(settings.env).not.toHaveProperty(HEADER)
      expect(settings.env.CUSTOM).toBe('keep')
      expect(settings.permissions).toEqual(preserved.permissions)
      expect(settings.hooks).toEqual(preserved.hooks)
      expect(settings.customField).toEqual(preserved.customField)
      expect(settings.mcpServers).toEqual({ fixture: { command: 'fixture-mcp' } })
      f.run(code)
      expect(f.read()).toEqual(settings)
    } finally { f.cleanup() }
  })

  test('failed OmniRoute configure does not change settings', () => {
    const f = fixture()
    try {
      f.write(preserved)
      const before = readFileSync(f.settingsPath, 'utf8')
      f.run(`
        const { configureClient } = await import(${moduleUrl('modules/omniroute.ts')});
        if (await configureClient('claude-code') !== 7) process.exit(1);
      `, { OMNIROUTE_STUB_EXIT: '7' })
      expect(readFileSync(f.settingsPath, 'utf8')).toBe(before)
    } finally { f.cleanup() }
  })

  test('non-Claude OmniRoute configure does not clean Claude settings', () => {
    const f = fixture()
    try {
      f.write(preserved)
      const before = readFileSync(f.settingsPath, 'utf8')
      f.run(`
        const { configureClient } = await import(${moduleUrl('modules/omniroute.ts')});
        if (await configureClient('codex') !== 0) process.exit(1);
      `)
      expect(f.read().env[HEADER]).toBe('0')
      expect(readFileSync(f.settingsPath, 'utf8')).toBe(before)
    } finally { f.cleanup() }
  })
})
