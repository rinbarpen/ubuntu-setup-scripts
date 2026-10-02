import * as p from '@clack/prompts'
import color from 'picocolors'

/** Restore the tty so a crash or forced exit never leaves the shell in raw mode. */
export function restoreTerminal(): void {
  try {
    if (process.stdin.isTTY && process.stdin.isRaw) process.stdin.setRawMode(false)
  } catch {}
  try {
    if (process.stdout.isTTY) process.stdout.write('\x1b[?1049l\x1b[?25h')
  } catch {}
}

async function guarded<T>(fn: () => Promise<T>): Promise<T> {
  // @clack/prompts owns stdin's keypress parser and raw-mode lifecycle.
  // Adding a competing data listener forces flowing mode and interferes with
  // readline's redraw/input handling, so keep this wrapper behavior-free.
  return fn()
}

export function setupDoubleEscape(): void {
  // Retained for API compatibility; Clack handles prompt keypresses itself.
}

export function teardownPrompts(): void {
  restoreTerminal()
}

export function intro(label = 'rinbake'): void {
  p.intro(color.bgCyan(` ${label} `))
}

export function outro(msg: string): void {
  p.outro(msg)
}

export async function select<T extends string>(opts: {
  message: string
  options: { value: T; label: string; hint?: string }[]
}): Promise<T | symbol> {
  return guarded(() => p.select({
    message: opts.message,
    options: opts.options.map(o => ({
      value: o.value,
      label: o.label,
      hint: o.hint,
    })) as any,
  }))
}

export async function multiselect<T extends string>(opts: {
  message: string
  options: { value: T; label: string; hint?: string; checked?: boolean }[]
  required?: boolean
}): Promise<(T | symbol)[]> {
  return guarded(() => p.multiselect({
    message: opts.message,
    options: opts.options.map(o => ({
      value: o.value as string,
      label: o.label,
      hint: o.hint,
      checked: o.checked,
    })),
    required: opts.required ?? false,
  })) as Promise<(T | symbol)[]>
}

export async function input(opts: {
  message: string
  defaultValue?: string
  placeholder?: string
}): Promise<string | symbol> {
  return guarded(() => p.text({
    message: opts.message,
    defaultValue: opts.defaultValue,
    placeholder: opts.placeholder,
  }))
}

export async function password(opts: {
  message: string
}): Promise<string | symbol> {
  return guarded(() => p.password({
    message: opts.message,
  }))
}

/**
 * True when there is a real terminal to prompt on. Piped or redirected stdin
 * cannot answer a question, so callers should pick a default instead of
 * blocking forever on a prompt nobody can see.
 */
export function isInteractive(): boolean {
  return Boolean(process.stdin.isTTY && process.stdout.isTTY)
}

export async function confirm(opts: {
  message: string
  defaultValue?: boolean
}): Promise<boolean | symbol> {
  return guarded(() => p.confirm({
    message: opts.message,
    initialValue: opts.defaultValue,
  }))
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
