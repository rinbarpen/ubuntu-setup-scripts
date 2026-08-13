#!/usr/bin/env bun
/**
 * Unit tests for rinbake modules — programmatic, no TTY required.
 */
import { describe, test, expect } from 'bun:test'
import { getAllModules, getModule } from '../src/modules'
import { getMcpServers, getAllMcpIds, getMcpDef } from '../src/modules/mcp'
import { getKey, setKey, listKeys } from '../src/config/keys'
import {
  parseAuthStatus,
  sanitizeDiagnostic,
  detectGithubCli,
  installGithubCli,
  configureGithubCli,
} from '../src/modules/system/github-cli'

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
  readInstalled: () => Promise<string[]>
  writeInstalled: (ids: string[]) => Promise<void>
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
  const writeInstalledCalls: string[][] = []
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
    readInstalled: options.readInstalled ?? (async () => []),
    writeInstalled: async (ids: string[]) => writeInstalledCalls.push([...ids]),
  }

  return {
    deps: deps satisfies ConfigureDeps,
    calls,
    logs,
    warnings,
    confirmOptions,
    writeInstalledCalls,
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

  test('getModule by known id', () => {
    const mod = getModule('shell')
    expect(mod).toBeDefined()
    expect(mod!.id).toBe('shell')
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

  test('all modules are unique', () => {
    const modules = getAllModules()
    const ids = modules.map(m => m.id)
    expect(new Set(ids).size).toBe(ids.length)
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

  // Unit contract: configure observes this extra seam but never writes installed state.
  test('configure does not call the installed-state write seam when configuration fails', async () => {
    const installed = ['github-cli']
    const readInstalled = async () => {
      return [...installed]
    }
    const fixture = configureFixture({
      statuses: [new Error('gh status failed')],
      readInstalled,
    })
    const before = await readInstalled()
    await configureGithubCli(fixture.deps)
    const after = await readInstalled()

    expect(after).toEqual(before)
    expect(fixture.writeInstalledCalls).toEqual([])
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
