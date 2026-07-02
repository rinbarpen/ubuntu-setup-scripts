import { $ } from 'bun'
import type { KeyEntry } from '../types'
import { input, password, logInfo, logWarn } from '../utils/ui'

const KEYS_DIR = `${process.env.HOME || '/root'}/.config/rinbake`
const KEYS_PATH = `${KEYS_DIR}/keys.env`

async function ensureDir(): Promise<void> {
  await $`mkdir -p ${KEYS_DIR}`.nothrow()
}

export async function getKey(name: string): Promise<string | null> {
  if (process.env[name]) return process.env[name]!
  try {
    const file = Bun.file(KEYS_PATH)
    if (!(await file.exists())) return null
    const text = await file.text()
    const match = text.match(new RegExp(`^${name}=["']?(.*?)["']?$`, 'm'))
    return match ? match[1] : null
  } catch {
    return null
  }
}

export async function setKey(name: string, value: string): Promise<void> {
  await ensureDir()
  process.env[name] = value
  const file = Bun.file(KEYS_PATH)
  let text = (await file.exists()) ? await file.text() : ''
  const regex = new RegExp(`^${name}=.*$`, 'm')
  if (regex.test(text)) {
    text = text.replace(regex, `${name}=${value}`)
  } else {
    text += `\n${name}=${value}`
  }
  await Bun.write(KEYS_PATH, text.trim() + '\n')
}

export async function listKeys(): Promise<KeyEntry[]> {
  try {
    const file = Bun.file(KEYS_PATH)
    if (!(await file.exists())) return []
    const text = await file.text()
    return text
      .split('\n')
      .filter(line => line.includes('='))
      .map(line => {
        const idx = line.indexOf('=')
        return { name: line.slice(0, idx), value: line.slice(idx + 1) }
      })
  } catch {
    return []
  }
}

export async function promptAndSetKey(name: string, label?: string): Promise<string | null> {
  const existing = await getKey(name)
  if (existing) {
    logInfo(`${label || name}: ${maskKey(existing)}`)
    return existing
  }
  const val = name.toLowerCase().includes('key') || name.toLowerCase().includes('token')
    ? await password({ message: `${label || name}:` })
    : await input({ message: `${label || name}:` })

  if (typeof val !== 'string' || !val.trim()) {
    logWarn(`跳过 ${label || name}`)
    return null
  }
  await setKey(name, val.trim())
  return val.trim()
}

function maskKey(val: string): string {
  if (val.length <= 8) return '****'
  return `${val.slice(0, 4)}...${val.slice(-4)}`
}
