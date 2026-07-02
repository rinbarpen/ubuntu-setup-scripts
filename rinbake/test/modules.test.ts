#!/usr/bin/env bun
/**
 * Unit tests for rinbake modules — programmatic, no TTY required.
 */
import { describe, test, expect } from 'bun:test'
import { getAllModules, getModule } from '../src/modules'
import { getMcpServers, getAllMcpIds, getMcpDef } from '../src/modules/mcp'
import { getKey, setKey, listKeys } from '../src/config/keys'

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
