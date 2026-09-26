import { $ } from 'bun'
import { logInfo, logWarn } from './ui'

/**
 * Multi-user identity resolution.
 *
 * rinbake is frequently launched as `sudo rinbake init`. If we then trusted
 * $HOME we would write the invoking user's dotfiles into /root and leave a
 * trail of root-owned files that break their shell. Everything in this module
 * therefore resolves the *target* user, which is the real account behind a
 * sudo escalation, and never the root account itself.
 */

export interface Identity {
  /** Account whose home directory user-scope work targets. */
  user: string
  home: string
  /** True when rinbake itself is running with uid 0. */
  elevated: boolean
  /** True when the elevated shell was entered via sudo rather than a root login. */
  viaSudo: boolean
}

function readPasswdHome(user: string): string | null {
  const proc = Bun.spawnSync(['getent', 'passwd', user], {
    stdio: ['ignore', 'pipe', 'ignore'],
  })
  if (proc.exitCode !== 0) return null
  const line = proc.stdout.toString().trim()
  if (!line) return null
  const parts = line.split(':')
  return parts.length >= 6 && parts[5] ? parts[5] : null
}

export interface IdentityInput {
  euid: number
  sudoUser?: string
  user?: string
  logname?: string
  envHome?: string
  /** Home directory from the passwd database, when the account exists. */
  passwdHome?: string | null
}

/**
 * Pure identity decision, split out so the multi-user rules are testable
 * without actually being root.
 */
export function pickIdentity(input: IdentityInput): Identity {
  const elevated = input.euid === 0
  const sudoUser = input.sudoUser?.trim() || ''
  const viaSudo = elevated && sudoUser.length > 0 && sudoUser !== 'root'

  // Under sudo the interesting account is SUDO_USER; a plain root login has
  // none, and then root genuinely is the target.
  const user = viaSudo
    ? sudoUser
    : (input.user || input.logname || '').trim() || 'root'

  // Which source wins depends on how we got here. Under sudo, $HOME is /root
  // and must be distrusted, so the passwd database decides. Otherwise the
  // user's own $HOME is authoritative -- it may legitimately differ from
  // /etc/passwd on NFS/ephemeral accounts -- with passwd as the fallback.
  const home = viaSudo
    ? input.passwdHome || input.envHome || '/root'
    : input.envHome || input.passwdHome || '/root'

  return { user, home, elevated, viaSudo }
}

let cached: Identity | null = null

export function resolveIdentity(): Identity {
  if (cached) return cached

  const euid = typeof process.geteuid === 'function' ? process.geteuid() : 0
  const user = (process.env.USER || process.env.LOGNAME || '').trim() || 'root'
  const sudoUser = process.env.SUDO_USER?.trim() || ''

  cached = pickIdentity({
    euid,
    sudoUser,
    user,
    logname: process.env.LOGNAME,
    envHome: process.env.HOME,
    passwdHome: readPasswdHome(sudoUser && sudoUser !== 'root' ? sudoUser : user),
  })
  return cached
}

/** For tests and for re-reading after the environment changes. */
export function resetIdentityCache(): void {
  cached = null
}

export function targetUser(): string {
  return resolveIdentity().user
}

export function targetHome(): string {
  return resolveIdentity().home
}

export function isElevated(): boolean {
  return resolveIdentity().elevated
}

/**
 * Announce which account user-scope work targets. Called once by commands that
 * touch the target home so a mistaken `sudo rinbake init` is visible up front.
 */
export function reportIdentity(): Identity {
  const id = resolveIdentity()
  if (id.viaSudo) {
    logInfo(`以 root 运行，用户级配置将写入 ${id.user} 的家目录 (${id.home})`)
  } else if (id.elevated) {
    logWarn(`以 root 运行，用户级配置将写入 ${id.home}；如需配置其他账号请用 sudo -u <用户> rinbake ...`)
  } else {
    logInfo(`用户级配置目标: ${id.user} (${id.home})`)
  }
  return id
}

/** Single-quote for /bin/sh, so a value can never break out of its argument. */
export function shQuote(value: string): string {
  return `'${value.replace(/'/g, `'\\''`)}'`
}

/**
 * Flatten a tagged template into a shell script.
 *
 * Needed because Bun's `$` expands an interpolated array into one argv entry
 * per element, and an interpolated string into a single quoted argv entry.
 * Neither can carry a `sudo -u ... <cmd>` prefix together with the template's
 * own shell syntax (pipes, globs, redirects): interpolating the raw
 * TemplateStringsArray makes sudo look for a command named "printf ".
 */
export function flattenTemplate(strings: TemplateStringsArray, values: unknown[]): string {
  let out = ''
  for (let i = 0; i < strings.length; i++) {
    out += strings[i]
    if (i < values.length) {
      const v = values[i]
      if (Array.isArray(v)) out += v.map(x => shQuote(String(x))).join(' ')
      else out += shQuote(String(v))
    }
  }
  return out
}

export interface RunAsUserResult {
  exitCode: number
  stdout: string
  stderr: string
}

/**
 * Run a command in the target user's context.
 *
 * When already elevated this drops back down with `sudo -u`, so a user-scope
 * step can never create root-owned files in that user's home. `-H` forces HOME
 * to the target account's home; without it sudo's env_reset would keep /root
 * and the files would land in the wrong place.
 *
 * Never throws: callers get the exit code and decide. A non-zero exit is
 * routine here (the key already exists, the tool is already installed) and an
 * unhandled rejection would abort the entire run.
 */
export async function runAsUser(strings: TemplateStringsArray, ...values: unknown[]): Promise<RunAsUserResult> {
  const id = resolveIdentity()

  // Already the right user: let Bun handle the template natively, including
  // its own escaping of interpolated values. .quiet() because Bun otherwise
  // tees the command's stdout to the terminal on top of capturing it, and
  // these steps (writing a config value, generating a key) produce no output
  // worth showing.
  if (!id.elevated || id.user === 'root') {
    const result = await $(strings, ...values).quiet().nothrow()
    return {
      exitCode: result.exitCode,
      stdout: result.stdout.toString().trim(),
      stderr: result.stderr.toString().trim(),
    }
  }

  const script = flattenTemplate(strings, values)
  const proc = Bun.spawn(['sudo', '-u', id.user, '-H', '/bin/sh', '-c', script], {
    stdout: 'pipe',
    stderr: 'pipe',
  })
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ])
  const exitCode = await proc.exited
  return { exitCode, stdout: stdout.trim(), stderr: stderr.trim() }
}

/**
 * Create a file inside the target user's home with that user as the owner.
 *
 * Bun.write always runs as the current (possibly root) process, so under
 * `sudo rinbake init` it would leave root-owned dotfiles the user cannot edit
 * later. Staging through a temp file and copying it as the user keeps ownership
 * correct. Returns false if the copy failed.
 */
export async function writeAsUser(path: string, content: string): Promise<boolean> {
  const id = resolveIdentity()
  const dir = path.slice(0, Math.max(path.lastIndexOf('/'), 1))

  if (!id.elevated || id.user === 'root') {
    await $`mkdir -p ${dir}`.quiet().nothrow()
    await Bun.write(path, content)
    return true
  }

  const tmp = `/tmp/.rinbake-${crypto.randomUUID()}`
  await Bun.write(tmp, content)
  try {
    // mkdir and cp both run as the user, so the directory and the file end up
    // owned by the account that will actually read them.
    const mk = await runAsUser`mkdir -p ${dir}`
    if (mk.exitCode !== 0) {
      logWarn(`创建目录失败: ${dir} — ${mk.stderr || mk.stdout}`)
      return false
    }
    const cp = await runAsUser`cp ${tmp} ${path}`
    if (cp.exitCode !== 0) {
      logWarn(`写入失败: ${path} — ${cp.stderr || cp.stdout}`)
      return false
    }
    return true
  } finally {
    await Bun.$`rm -f ${tmp}`.nothrow()
  }
}

/** True when a module's scope implies the run may need root. */
export function scopeNeedsSudo(scope: string | undefined): boolean {
  return scope === 'system' || scope === 'mixed'
}
