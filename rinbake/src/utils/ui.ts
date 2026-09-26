import * as p from '@clack/prompts'
import color from 'picocolors'

// Long enough for the rest of an escape sequence to arrive in the same read.
// TTY/PTY input can split one key sequence across reads with a noticeable gap.
// Keep this comfortably above typical inter-read jitter so an arrow key is not
// mistaken for a bare ESC followed by unrelated input.
const ESC_SEQ_WAIT_MS = 100
// Max gap between two bare ESC presses for it to count as "double ESC".
const DOUBLE_ESC_MS = 600

let seqTimer: ReturnType<typeof setTimeout> | null = null
let firstEsc = 0
let scan: EscScanState = createEscScanState()
let escListenerAttached = false
let promptDepth = 0

export interface EscScanState {
  inCsi: boolean
  pending: boolean
}

export function createEscScanState(): EscScanState {
  return { inCsi: false, pending: false }
}

/**
 * Consume raw tty bytes, tracking whether an ESC was a bare keypress.
 *
 * Arrow and function keys are transmitted as ESC [ <byte>, so a naive "any 0x1b
 * byte is an ESC press" check counts every cursor move as a press and exits as
 * soon as the user moves down twice. An ESC only sets `pending` here; the caller
 * confirms it via ESC_SEQ_WAIT_MS once no sequence byte follows.
 */
export function scanEsc(bytes: Iterable<number>, state: EscScanState): void {
  for (const byte of bytes) {
    if (state.inCsi) {
      // A CSI run ends at a final byte in 0x40-0x7e.
      if (byte >= 0x40 && byte <= 0x7e) state.inCsi = false
      continue
    }
    if (state.pending) {
      state.pending = false
      // '[' introduces CSI, 'O' introduces SS3: a named key, not a bare ESC.
      if (byte === 0x5b || byte === 0x4f) state.inCsi = true
      continue
    }
    if (byte === 0x1b) state.pending = true
  }
}

function registerEscPress(): void {
  const now = Date.now()
  if (firstEsc && now - firstEsc < DOUBLE_ESC_MS) {
    restoreTerminal()
    process.exit(0)
  }
  firstEsc = now
}

function onStdinData(chunk: Buffer): void {
  // A timeout belongs to the previously observed input boundary. Always
  // cancel it before consuming another chunk: that chunk may complete an
  // escape sequence (or begin a new one) split by the tty stream.
  if (seqTimer) {
    clearTimeout(seqTimer)
    seqTimer = null
  }
  scanEsc(chunk, scan)
  if (!scan.pending) return
  seqTimer = setTimeout(() => {
    seqTimer = null
    if (!scan.pending) return
    scan.pending = false
    registerEscPress()
  }, ESC_SEQ_WAIT_MS)
}

function onStdinError(err: Error): void {
  p.log.warn(`stdin 读取失败: ${err.message}`)
}

/** Restore the tty so a crash or forced exit never leaves the shell in raw mode. */
export function restoreTerminal(): void {
  try {
    if (process.stdin.isTTY && process.stdin.isRaw) process.stdin.setRawMode(false)
  } catch {}
  try {
    if (process.stdout.isTTY) process.stdout.write('\x1b[?1049l\x1b[?25h')
  } catch {}
}

/**
 * Only listen while a prompt is on screen. Holding the listener for the whole
 * run makes the parent drain the tty, so children that inherit stdin (notably
 * the `sudo -v` in sudoCheck, which must read the password) compete with it for
 * input, and a stray double ESC during a long install kills the run outright.
 */
function enterPrompt(): void {
  promptDepth++
  if (escListenerAttached || !process.stdin.isTTY) return
  escListenerAttached = true
  process.stdin.on('data', onStdinData)
  process.stdin.on('error', onStdinError)
  process.stdin.resume()
}

function exitPrompt(): void {
  promptDepth = Math.max(0, promptDepth - 1)
  if (promptDepth > 0 || !escListenerAttached) return
  escListenerAttached = false
  process.stdin.off('data', onStdinData)
  process.stdin.off('error', onStdinError)
  if (seqTimer) {
    clearTimeout(seqTimer)
    seqTimer = null
  }
  firstEsc = 0
  scan = createEscScanState()
  try {
    process.stdin.pause()
  } catch {}
}

async function guarded<T>(fn: () => Promise<T>): Promise<T> {
  enterPrompt()
  try {
    return await fn()
  } finally {
    exitPrompt()
  }
}

export function setupDoubleEscape(): void {
  enterPrompt()
}

export function teardownPrompts(): void {
  while (promptDepth > 0) exitPrompt()
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
