import * as p from '@clack/prompts'
import color from 'picocolors'

let escTimer: ReturnType<typeof setTimeout> | null = null
let firstEsc = 0
let escListenerAttached = false

export function setupDoubleEscape(): void {
  if (!process.stdin.isTTY || escListenerAttached) return
  escListenerAttached = true
  process.stdin.on('data', (chunk: Buffer) => {
    for (const byte of chunk) {
      if (byte === 0x1b) {
        const now = Date.now()
        if (firstEsc && now - firstEsc < 600) {
          process.exit(0)
        }
        firstEsc = now
        if (escTimer) clearTimeout(escTimer)
        escTimer = setTimeout(() => { firstEsc = 0 }, 600)
      }
    }
  })
}

export function intro(label = 'rinbake'): void {
  setupDoubleEscape()
  p.intro(color.bgCyan(` ${label} `))
}

export function outro(msg: string): void {
  p.outro(msg)
}

export async function select<T extends string>(opts: {
  message: string
  options: { value: T; label: string; hint?: string }[]
}): Promise<T | symbol> {
  return p.select({
    message: opts.message,
    options: opts.options.map(o => ({
      value: o.value,
      label: o.label,
      hint: o.hint,
    })),
  })
}

export async function multiselect<T extends string>(opts: {
  message: string
  options: { value: T; label: string; hint?: string; checked?: boolean }[]
  required?: boolean
}): Promise<(T | symbol)[]> {
  return p.multiselect({
    message: opts.message,
    options: opts.options.map(o => ({
      value: o.value as string,
      label: o.label,
      hint: o.hint,
      checked: o.checked,
    })),
    required: opts.required ?? false,
  }) as Promise<(T | symbol)[]>
}

export async function input(opts: {
  message: string
  defaultValue?: string
  placeholder?: string
}): Promise<string | symbol> {
  return p.text({
    message: opts.message,
    defaultValue: opts.defaultValue,
    placeholder: opts.placeholder,
  })
}

export async function password(opts: {
  message: string
}): Promise<string | symbol> {
  return p.password({
    message: opts.message,
  })
}

export async function confirm(opts: {
  message: string
  defaultValue?: boolean
}): Promise<boolean | symbol> {
  return p.confirm({
    message: opts.message,
    initialValue: opts.defaultValue,
  })
}

export function logInfo(msg: string): void {
  p.log.info(msg)
}

export function logWarn(msg: string): void {
  p.log.warn(msg)
}

export function logError(msg: string): void {
  p.log.error(msg)
}

export function logStep(msg: string): void {
  p.log.message(color.dim('→') + ' ' + msg)
}

export function isCancelled<T>(val: T | symbol): val is symbol {
  return p.isCancel(val)
}
