#!/usr/bin/env bun
/**
 * Unit tests for rinbake modules — programmatic, no TTY required.
 */
import { describe, test, expect } from 'bun:test'
import { getAllModules, getModule } from '../src/modules'
import { getMcpServers, getAllMcpIds, getMcpDef } from '../src/modules/mcp'
import { getKey, setKey, listKeys } from '../src/config/keys'
import { readInstalled } from '../src/config/manager'
import { createEscScanState, scanEsc } from '../src/utils/ui'
import {
  OMNIROUTE_CLIENTS,
  OMNIROUTE_PROVIDER_PRESETS,
  OMNIROUTE_API_KEY,
  OMNIROUTE_DEFAULT_MODEL,
  getOmniRouteBaseUrl,
  getOmniRouteClientUrl,
  getOmniRouteProvider,
} from '../src/config/omniroute'
import {
  parseAuthStatus,
  sanitizeDiagnostic,
  detectGithubCli,
  installGithubCli,
  configureGithubCli,
} from '../src/modules/system/github-cli'
import {
  buildOrcaServiceUnit,
  selectOrcaAsset,
} from '../src/modules/agents/orca'
import {
  mergePaseoConfig,
  paseoHostnames,
} from '../src/modules/agents/paseo'

type GhResult = { exitCode: number; stdout: string; stderr: string }
type GhCall = { args: string[]; interactive: boolean }
type ConfirmOptions = { defaultValue?: boolean }
type InstallDeps = {
  detect: () => Promise<boolean>
  installGh: (pkg: string) => Promise<boolean>
}
type ConfigureDeps = {
  detect: () => Promise<boolean>
  isTTY: boolean
  confirm: (opts: ConfirmOptions) => Promise<boolean | symbol>
  runGh: (args: string[], interactive?: boolean) => Promise<GhResult>
  logInfo: (message: string) => void
  logWarn: (message: string) => void
}

const statusCall: GhCall = {
  args: ['auth', 'status', '--json', 'hosts'],
  interactive: false,
}
const loginCall: GhCall = {
  args: ['auth', 'login'],
  interactive: true,
}

const authenticatedStatus = JSON.stringify({
  hosts: {
    'github.com': [{ state: 'success', host: 'github.com', login: 'ROLE', token: 'TOKEN' }],
  },
})
const unauthenticatedStatus = JSON.stringify({
  hosts: { 'github.com': [{ state: 'error' }] },
})

function ghResult(stdout: string, exitCode = 0, stderr = ''): GhResult {
  return { exitCode, stdout, stderr }
}

function configureFixture(options: {
  installed?: boolean
  tty?: boolean
  statuses?: Array<GhResult | Error>
  login?: GhResult | Error
  confirmResult?: boolean | symbol
  readInstalled?: () => Promise<string[]>
} = {}) {
  const calls: GhCall[] = []
  const logs: string[] = []
  const warnings: string[] = []
  const confirmOptions: ConfirmOptions[] = []
  const statuses = [...(options.statuses ?? [ghResult(authenticatedStatus)])]
  const login = options.login ?? ghResult('')

  const deps = {
    detect: async () => options.installed ?? true,
    isTTY: options.tty ?? true,
    confirm: async (opts: ConfirmOptions) => {
      confirmOptions.push(opts)
      return options.confirmResult ?? false
    },
    runGh: async (args: string[], interactive = false): Promise<GhResult> => {
      calls.push({ args, interactive })
      const isStatus = args.length === 4 && args[0] === 'auth' && args[1] === 'status'
        && args[2] === '--json' && args[3] === 'hosts'
      const result = isStatus ? statuses.shift() : login
      if (result instanceof Error) throw result
      return result ?? ghResult('')
    },
    logInfo: (message: string) => logs.push(message),
    logWarn: (message: string) => warnings.push(message),
  }

  return {
    deps: deps satisfies ConfigureDeps,
    calls,
    logs,
    warnings,
    confirmOptions,
  }
}

function expectExactCalls(calls: GhCall[], expected: GhCall[]): void {
  expect(calls).toEqual(expected)
  for (const call of expected) {
    if (call.args[1] === 'status') {
      expect(call.args).toEqual(statusCall.args)
      expect(call.args).not.toContain('--show-token')
      expect(call.interactive).toBe(false)
    }
    if (call.args[1] === 'login') {
      expect(call.args).toEqual(loginCall.args)
      expect(call.interactive).toBe(true)
    }
  }
}

function expectNoCalls(calls: GhCall[]): void {
  expect(calls).toEqual([])
}

function fixtureOutput(fixture: ReturnType<typeof configureFixture>): string {
  return [...fixture.logs, ...fixture.warnings].join('\n')
}

// ─── Module Registration ──────────────────────────

describe('module registration', () => {
  test('all modules have required fields', () => {
    const modules = getAllModules()
    expect(modules.length).toBeGreaterThan(0)
    for (const m of modules) {
      expect(m.id).toBeTruthy()
      expect(m.label).toBeTruthy()
      expect(m.description).toBeTruthy()
      expect(m.category).toMatch(/^(system|agent|other)$/)
      expect(typeof m.install).toBe('function')
    }
  })

  test('getModule returns undefined for unknown', () => {
    expect(getModule('nonexistent')).toBeUndefined()
  })

  test('vibma is removed from module registration', () => {
    expect(getAllModules().map(module => module.id)).not.toContain('vibma')
    expect(getModule('vibma')).toBeUndefined()
  })

  test('getModule by known id', () => {
    const mod = getModule('shell')
    expect(mod).toBeDefined()
    expect(mod!.id).toBe('shell')
  })

  test('legacy relay is no longer a registered module', () => {
    expect(getModule('relay')).toBeUndefined()
  })

  test('github-cli is an enabled system module with configuration', () => {
    const mod = getModule('github-cli')
    expect(mod).toBeDefined()
    expect(mod!.id).toBe('github-cli')
    expect(mod!.enabled).toBe(true)
    expect(mod!.category).toBe('system')
    expect(`${mod!.label} ${mod!.description}`).toMatch(/GitHub/i)
    expect(`${mod!.label} ${mod!.description}`).toMatch(/CLI/i)
    expect(`${mod!.label} ${mod!.description}`).toMatch(/认证|auth/i)
    expect(typeof mod!.configure).toBe('function')
  })

  test('omniroute is an enabled service module with lifecycle configuration', () => {
    const mod = getModule('omniroute')
    expect(mod).toBeDefined()
    expect(mod!.id).toBe('omniroute')
    expect(mod!.enabled).toBe(true)
    expect(mod!.category).toBe('other')
    expect(mod!.label).toMatch(/OmniRoute/i)
    expect(typeof mod!.install).toBe('function')
    expect(typeof mod!.update).toBe('function')
    expect(typeof mod!.configure).toBe('function')
    expect(typeof mod!.detect).toBe('function')
  })

  test('paseo and orca are registered agent modules with configuration', () => {
    const paseo = getModule('paseo')
    const orca = getModule('orca')
    expect(paseo).toMatchObject({ id: 'paseo', category: 'agent', enabled: true })
    expect(orca).toMatchObject({ id: 'orca', category: 'agent', enabled: false })
    expect(typeof paseo!.configure).toBe('function')
    expect(typeof orca!.configure).toBe('function')
  })

  test('all modules are unique', () => {
    const modules = getAllModules()
    const ids = modules.map(m => m.id)
    expect(new Set(ids).size).toBe(ids.length)
  })
})

describe('Paseo configuration', () => {
  test('merges daemon settings without dropping unrelated fields', () => {
    const current = {
      custom: { keep: true },
      daemon: {
        listen: '127.0.0.1:6767',
        relay: { enabled: false, keepRelayField: 'yes' },
        mcp: { enabled: false, keepMcpField: 'yes' },
        auth: { password: 'HASH' },
      },
    }
    const merged = mergePaseoConfig(current, {
      listen: '0.0.0.0:6799',
      mcpEnabled: true,
      injectIntoAgents: true,
      relayEnabled: true,
      hostname: 'fixture-host',
    })

    expect(merged.custom).toEqual({ keep: true })
    expect(merged.daemon).toMatchObject({
      listen: '0.0.0.0:6799',
      auth: { password: 'HASH' },
      relay: { enabled: true, keepRelayField: 'yes' },
      mcp: { enabled: true, injectIntoAgents: true, keepMcpField: 'yes' },
      hostnames: ['localhost', '.localhost', 'fixture-host', '.fixture-host'],
    })
    expect(merged['$schema']).toContain('paseo.sh/schemas')
    expect(merged.version).toBe(1)
  })

  test('uses localhost hostnames for local listeners', () => {
    expect(paseoHostnames('127.0.0.1:6767')).toEqual(['localhost', '.localhost'])
    expect(paseoHostnames('[::1]:6767')).toEqual(['localhost', '.localhost'])
  })
})

describe('Orca installation metadata', () => {
  test('selects Linux AppImage assets by architecture', () => {
    expect(selectOrcaAsset('x86_64')).toBe('orca-linux.AppImage')
    expect(selectOrcaAsset('aarch64')).toBe('orca-linux-arm64.AppImage')
    expect(() => selectOrcaAsset('mips64')).toThrow(/不支持当前架构/)
  })

  test('builds a restartable headless service unit', () => {
    const unit = buildOrcaServiceUnit({
      port: 6768,
      pairingAddress: '100.64.1.20',
      serviceUser: 'orca',
      serviceHome: '/home/orca',
    })
    expect(unit).toContain('User=orca')
    expect(unit).toContain('ExecStart=/opt/orca/orca-linux.AppImage serve --port 6768 --pairing-address 100.64.1.20 --json')
    expect(unit).toContain('KillMode=mixed')
    expect(unit).toContain('RestartPreventExitStatus=3')
  })
})

describe('OmniRoute provider and client configuration', () => {
  test('provider presets include common API and web-auth providers', () => {
    const ids = OMNIROUTE_PROVIDER_PRESETS.map(provider => provider.id)
    expect(new Set(ids).size).toBe(ids.length)
    expect(ids).toEqual(expect.arrayContaining([
      'openai', 'anthropic', 'deepseek', 'openrouter', 'gemini', 'chatgpt-web', 'custom',
    ]))
    expect(OMNIROUTE_PROVIDER_PRESETS.find(provider => provider.id === 'chatgpt-web')).toMatchObject({
      auth: 'cookie',
      manualAuth: true,
    })
  })

  test('client endpoints use the correct OmniRoute protocol roots', () => {
    expect(getOmniRouteBaseUrl()).toBe('http://localhost:20128')
    expect(getOmniRouteClientUrl('codex')).toBe('http://localhost:20128/v1')
    expect(getOmniRouteClientUrl('opencode')).toBe('http://localhost:20128/v1')
    expect(getOmniRouteClientUrl('claude-code')).toBe('http://localhost:20128')
    expect(OMNIROUTE_CLIENTS.codex.protocol).toBe('openai-responses')
    expect(OMNIROUTE_CLIENTS['claude-code'].protocol).toBe('anthropic')
  })

  test('OmniRoute provider uses the local OpenAI-compatible gateway', () => {
    expect(OMNIROUTE_DEFAULT_MODEL).toBe('auto')
    expect(getOmniRouteProvider()).toEqual({
      id: 'omniroute',
      name: 'OmniRoute',
      baseUrl: 'http://localhost:20128/v1',
      envKey: OMNIROUTE_API_KEY,
      apiFormat: 'responses',
    })
  })
})

describe('module detect functions', () => {
  test('detect returns boolean', async () => {
    const modules = getAllModules()
    for (const m of modules) {
      if (m.detect) {
        const result = await m.detect()
        expect(typeof result).toBe('boolean')
      }
    }
  })

  test('github-cli detect returns a boolean', async () => {
    const mod = getModule('github-cli')
    expect(mod).toBeDefined()
    expect(typeof mod!.detect).toBe('function')
    const result = await mod!.detect!()
    expect(typeof result).toBe('boolean')
  })
})

describe('GitHub CLI auth status parsing', () => {
  test('sanitizes Bearer diagnostics before key-value redaction', () => {
    const sanitized = sanitizeDiagnostic('Authorization: Bearer SECRET_VALUE TOKEN')

    expect(sanitized).not.toContain('SECRET_VALUE')
    expect(sanitized).not.toContain('TOKEN')
    expect(sanitized.toLowerCase()).toContain('authorization')
    expect(sanitized).toContain('[redacted]')
  })

  test('sanitizes token Authorization diagnostics before key-value redaction', () => {
    const sanitized = sanitizeDiagnostic('Authorization: token SECRET_VALUE TOKEN')

    expect(sanitized).not.toContain('SECRET_VALUE')
    expect(sanitized).not.toContain('TOKEN')
  })

  test('parses a successful GitHub auth entry without exposing its token', () => {
    expect(parseAuthStatus(authenticatedStatus)).toEqual({
      authenticated: true,
      entries: [{ host: 'github.com', login: 'ROLE', state: 'success' }],
    })
  })

  test('reports unauthenticated entries when no host succeeds', () => {
    expect(parseAuthStatus(unauthenticatedStatus)).toEqual({
      authenticated: false,
      entries: [{ host: 'github.com', login: '', state: 'error' }],
    })
  })

  test('rejects malformed and empty auth status JSON', () => {
    expect(() => parseAuthStatus('{')).toThrow()
    expect(() => parseAuthStatus('{}')).toThrow()
  })

  test('detects the CLI independently from auth status parsing', async () => {
    expect(await detectGithubCli(async () => true)).toBe(true)
    expect(await detectGithubCli(async () => false)).toBe(false)
  })
})

describe('GitHub CLI installation', () => {
  test('skips apt when gh is already installed', async () => {
    const installCalls: string[] = []
    const installGh = async (pkg: string) => {
      installCalls.push(pkg)
      return true
    }
    const deps: InstallDeps = {
      detect: async () => true,
      installGh,
    }
    const result = await installGithubCli(deps)

    expect(result).toBe(true)
    expect(installCalls).toEqual([])
  })

  test('passes gh to apt and reports a false apt result', async () => {
    const installCalls: string[] = []
    const installGh = async (pkg: string) => {
      installCalls.push(pkg)
      return false
    }
    const deps: InstallDeps = {
      detect: async () => false,
      installGh,
    }
    await expect(installGithubCli(deps)).rejects.toThrow(/gh/)

    expect(installCalls).toEqual(['gh'])
  })

  test('reports an apt exception with gh in the error', async () => {
    const installCalls: string[] = []
    const installGh = async (pkg: string) => {
      installCalls.push(pkg)
      throw new Error('apt unavailable')
    }
    const deps: InstallDeps = {
      detect: async () => false,
      installGh,
    }
    await expect(installGithubCli(deps)).rejects.toThrow(/gh/)

    expect(installCalls).toEqual(['gh'])
  })

  test('fails when apt succeeds but gh remains undetectable', async () => {
    const detect = async () => false
    const installCalls: string[] = []
    const installGh = async (pkg: string) => {
      installCalls.push(pkg)
      return true
    }
    const deps: InstallDeps = { detect, installGh }
    await expect(installGithubCli(deps)).rejects.toThrow(/gh/)

    expect(installCalls).toEqual(['gh'])
  })

  test('returns success after apt installs a detectable gh', async () => {
    const detections = [false, true]
    const detect = async () => detections.shift() ?? false
    const installCalls: string[] = []
    const installGh = async (pkg: string) => {
      installCalls.push(pkg)
      return true
    }
    const deps: InstallDeps = { detect, installGh }
    const result = await installGithubCli(deps)

    expect(result).toBe(true)
    expect(installCalls).toEqual(['gh'])
  })
})

describe('GitHub CLI authentication configuration', () => {
  test('only logs when gh is not installed', async () => {
    const fixture = configureFixture({ installed: false })
    await configureGithubCli(fixture.deps)

    expectNoCalls(fixture.calls)
    expect(fixtureOutput(fixture)).toMatch(/gh/)
  })

  test('does not log in when auth status exits non-zero', async () => {
    const fixture = configureFixture({
      statuses: [ghResult(authenticatedStatus, 7, 'gh auth status failed TOKEN')],
      confirmResult: true,
    })
    await configureGithubCli(fixture.deps)

    expectExactCalls(fixture.calls, [statusCall])
    expect(fixtureOutput(fixture)).toMatch(/failed/i)
    expect(fixtureOutput(fixture)).not.toContain('TOKEN')
  })

  test('uses sanitized stdout when stderr is only whitespace', async () => {
    const fixture = configureFixture({
      statuses: [ghResult('useful failure TOKEN', 7, ' \n\t')],
    })
    await configureGithubCli(fixture.deps)

    expect(fixtureOutput(fixture)).toContain('useful failure')
    expect(fixtureOutput(fixture)).not.toContain('TOKEN')
  })

  test('does not log in when auth status throws', async () => {
    const fixture = configureFixture({ statuses: [new Error('gh auth status failed TOKEN')] })
    await configureGithubCli(fixture.deps)

    expectExactCalls(fixture.calls, [statusCall])
    expect(fixtureOutput(fixture)).toMatch(/failed/i)
    expect(fixtureOutput(fixture)).not.toContain('TOKEN')
  })

  test('does not log in when auth status is invalid JSON', async () => {
    const fixture = configureFixture({
      statuses: [ghResult('{', 0, 'gh auth status returned invalid JSON TOKEN')],
    })
    await configureGithubCli(fixture.deps)

    expectExactCalls(fixture.calls, [statusCall])
    expect(fixtureOutput(fixture)).toMatch(/invalid/i)
    expect(fixtureOutput(fixture)).not.toContain('TOKEN')
  })

  test('uses a false confirmation default for an authenticated TTY', async () => {
    const fixture = configureFixture({
      statuses: [ghResult(authenticatedStatus)],
      confirmResult: false,
    })
    await configureGithubCli(fixture.deps)

    expect(fixture.confirmOptions[0]?.defaultValue).toBe(false)
    expectExactCalls(fixture.calls, [statusCall])
  })

  test('does not log in when an authenticated TTY confirmation is cancelled', async () => {
    const fixture = configureFixture({
      statuses: [ghResult(authenticatedStatus)],
      confirmResult: Symbol('cancel'),
    })
    await configureGithubCli(fixture.deps)

    expectExactCalls(fixture.calls, [statusCall])
  })

  test('keeps authenticated status visible without a TTY', async () => {
    const fixture = configureFixture({
      tty: false,
      statuses: [ghResult(authenticatedStatus)],
    })
    await configureGithubCli(fixture.deps)

    expectExactCalls(fixture.calls, [statusCall])
    expect(fixture.confirmOptions).toEqual([])
    expect(fixture.logs.join('\n')).toContain('github.com')
    expect(fixtureOutput(fixture)).not.toContain('TOKEN')
  })

  test('logs in on confirmation and rechecks auth status', async () => {
    const fixture = configureFixture({
      statuses: [ghResult(authenticatedStatus), ghResult(authenticatedStatus)],
      confirmResult: true,
    })
    await configureGithubCli(fixture.deps)

    expectExactCalls(fixture.calls, [statusCall, loginCall, statusCall])
  })

  test('logs in from an unauthenticated TTY and rechecks auth status', async () => {
    const fixture = configureFixture({
      statuses: [ghResult(unauthenticatedStatus), ghResult(authenticatedStatus)],
    })
    await configureGithubCli(fixture.deps)

    expectExactCalls(fixture.calls, [statusCall, loginCall, statusCall])
  })

  test('does not log in without a TTY and explains the gh auth login command', async () => {
    const fixture = configureFixture({
      tty: false,
      statuses: [ghResult(unauthenticatedStatus)],
    })
    await configureGithubCli(fixture.deps)

    expectExactCalls(fixture.calls, [statusCall])
    expect(fixtureOutput(fixture)).toContain('gh auth login')
  })

  test('warns instead of throwing when login exits non-zero', async () => {
    const fixture = configureFixture({
      statuses: [ghResult(unauthenticatedStatus)],
      login: ghResult('', 1, 'gh auth login failed TOKEN'),
    })
    await configureGithubCli(fixture.deps)

    expectExactCalls(fixture.calls, [statusCall, loginCall])
    expect(fixture.warnings.join('\n')).toMatch(/failed/i)
    expect(fixture.warnings.join('\n')).not.toContain('TOKEN')
  })

  test('warns when successful login is followed by an unauthenticated recheck', async () => {
    const fixture = configureFixture({
      statuses: [
        ghResult(unauthenticatedStatus),
        ghResult(unauthenticatedStatus, 0, 'gh auth status post-login failure TOKEN'),
      ],
    })
    await configureGithubCli(fixture.deps)

    expectExactCalls(fixture.calls, [statusCall, loginCall, statusCall])
    expect(fixture.warnings.join('\n')).toMatch(/failure|failed/i)
    expect(fixture.warnings.join('\n')).not.toContain('TOKEN')
  })

  test('warns when the post-login auth recheck returns invalid JSON', async () => {
    const fixture = configureFixture({
      statuses: [
        ghResult(unauthenticatedStatus),
        ghResult('{', 0, 'gh auth status post-login failure TOKEN'),
      ],
    })
    await configureGithubCli(fixture.deps)

    expectExactCalls(fixture.calls, [statusCall, loginCall, statusCall])
    expect(fixture.warnings.join('\n')).toMatch(/failure|failed|invalid/i)
    expect(fixture.warnings.join('\n')).not.toContain('TOKEN')
  })

  test('never logs the raw auth JSON or token', async () => {
    const fixture = configureFixture({ statuses: [ghResult(authenticatedStatus)] })
    await configureGithubCli(fixture.deps)
    const output = [...fixture.logs, ...fixture.warnings].join('\n')

    expect(output).not.toContain('TOKEN')
  })

  test('configuration failure leaves installed state unchanged', async () => {
    const fixture = configureFixture({ statuses: [new Error('gh status failed')] })
    const before = await readInstalled()
    await configureGithubCli(fixture.deps)
    const after = await readInstalled()

    expect(after).toEqual(before)
  })
})

// ─── MCP Registry ─────────────────────────────────

describe('MCP registry', () => {
  test('getAllMcpIds returns all servers', () => {
    const ids = getAllMcpIds()
    expect(ids.length).toBeGreaterThanOrEqual(7)
    expect(ids).toContain('context7')
    expect(ids).toContain('brave-search')
    expect(ids).toContain('github')
  })

  test('getMcpDef returns definition', () => {
    const def = getMcpDef('context7')
    expect(def).toBeDefined()
    expect(def!.command).toBe('npx')
    expect(def!.args).toContain('@upstash/context7-mcp@latest')
  })

  test('getMcpServers with no selection returns all', () => {
    const all = getMcpServers([])
    expect(Object.keys(all).length).toBe(getAllMcpIds().length)
  })

  test('getMcpServers filters by selection', () => {
    const subset = getMcpServers(['context7', 'brave-search'])
    expect(Object.keys(subset)).toEqual(['context7', 'brave-search'])
  })

  test('getMcpDef returns undefined for unknown', () => {
    expect(getMcpDef('nonexistent')).toBeUndefined()
  })
})

// ─── API Key Management ──────────────────────────

describe('API key management', () => {
  test('setKey and getKey roundtrip', async () => {
    await setKey('TEST_KEY_A', 'secret-value-123')
    const val = await getKey('TEST_KEY_A')
    expect(val).toBe('secret-value-123')
  })

  test('getKey returns null for missing', async () => {
    const val = await getKey('NONEXISTENT_KEY_X')
    expect(val).toBeNull()
  })

  test('listKeys returns stored keys', async () => {
    await setKey('TEST_KEY_B', 'another-value-456')
    const keys = await listKeys()
    const found = keys.find(k => k.name === 'TEST_KEY_B')
    expect(found).toBeDefined()
    expect(found!.value).toBe('another-value-456')
  })

  test('setKey overwrites existing', async () => {
    await setKey('TEST_KEY_A', 'updated-value')
    const val = await getKey('TEST_KEY_A')
    expect(val).toBe('updated-value')
  })

})

// ─── Module type structure ──────────────────────

describe('module structure', () => {
  test('openclaw is disabled by default', () => {
    const mod = getModule('openclaw')
    expect(mod).toBeDefined()
    expect(mod!.enabled).toBe(false)
  })

  test('system modules are enabled by default', () => {
    for (const id of ['ubuntu-base', 'languages', 'shell', 'fisher', 'git']) {
      const mod = getModule(id)
      expect(mod).toBeDefined()
      expect(mod!.enabled).toBe(true)
    }
  })
})

// ─── ESC sequence handling ──────────────────────
// Regression: arrow keys are sent as ESC [ <byte>. Treating every 0x1b byte as
// an ESC press made `rinbake init` exit as soon as the cursor moved down twice,
// which looked like a crash on the third list item.

describe('scanEsc', () => {
  const DOWN = [0x1b, 0x5b, 0x42] // ESC [ B
  const UP = [0x1b, 0x5b, 0x41] // ESC [ A
  const RIGHT = [0x1b, 0x5b, 0x43] // ESC [ C
  const F1 = [0x1b, 0x4f, 0x50] // ESC O P

  test('arrow keys never register a bare ESC', () => {
    for (const seq of [DOWN, UP, RIGHT, F1]) {
      const state = createEscScanState()
      scanEsc(seq, state)
      expect(state.pending).toBe(false)
      expect(state.inCsi).toBe(false)
    }
  })

  test('two arrow keys in one chunk do not register a bare ESC', () => {
    const state = createEscScanState()
    scanEsc([...DOWN, ...DOWN], state)
    expect(state.pending).toBe(false)
  })

  test('repeated cursor movement stays clean', () => {
    const state = createEscScanState()
    for (let i = 0; i < 20; i++) scanEsc(DOWN, state)
    for (let i = 0; i < 20; i++) scanEsc(UP, state)
    expect(state.pending).toBe(false)
    expect(state.inCsi).toBe(false)
  })

  test('a lone ESC stays pending for the caller to confirm', () => {
    const state = createEscScanState()
    scanEsc([0x1b], state)
    expect(state.pending).toBe(true)
  })

  test('ESC split across reads is still treated as a sequence', () => {
    const state = createEscScanState()
    scanEsc([0x1b], state) // first read only got the ESC
    scanEsc([0x5b], state) // second read got '['
    expect(state.inCsi).toBe(true)
    scanEsc([0x42], state) // final byte 'B'
    expect(state.inCsi).toBe(false)
    expect(state.pending).toBe(false)
  })

  test('non-escape keys are ignored', () => {
    const state = createEscScanState()
    // enter, space, 'a', then F3 (ESC [ 1 3 ~) which has a multi-digit body
    scanEsc([0x0d, 0x20, 0x61, 0x1b, 0x5b, 0x31, 0x33, 0x7e], state)
    expect(state.pending).toBe(false)
    expect(state.inCsi).toBe(false)
  })
})
