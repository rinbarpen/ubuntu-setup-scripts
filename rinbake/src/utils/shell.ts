export async function hasCommand(name: string): Promise<boolean> {
  const proc = Bun.spawnSync(['which', name], { stdio: ['ignore', 'pipe', 'pipe'] })
  return proc.exitCode === 0 && proc.stdout.toString().trim().length > 0
}

export async function hasPkg(pkg: string): Promise<boolean> {
  const proc = Bun.spawnSync(['dpkg', '-s', pkg], { stdio: ['ignore', 'pipe', 'pipe'] })
  return proc.exitCode === 0
}

export async function run(cmdStr: string): Promise<{ exitCode: number; stdout: string; stderr: string }> {
  const proc = Bun.spawnSync(['sh', '-c', cmdStr], { stdio: ['ignore', 'pipe', 'pipe'] })
  return {
    exitCode: proc.exitCode,
    stdout: proc.stdout.toString().trim(),
    stderr: proc.stderr.toString().trim(),
  }
}

export function appendBashrc(lines: string): string {
  return `
# --- rinbake ---
${lines}
# --- rinbake end ---`
}

export async function appendToBashrcIfMissing(marker: string, content: string): Promise<void> {
  const home = process.env.HOME || '/root'
  const bashrcPath = `${home}/.bashrc`
  const file = Bun.file(bashrcPath)
  const exists = await file.exists()
  const text = exists ? await file.text() : ''
  if (text.includes(marker)) return
  await Bun.write(bashrcPath, text + '\n' + appendBashrc(content) + '\n')
}

export async function writeFishFunction(name: string, body: string): Promise<void> {
  const home = process.env.HOME || '/root'
  const dir = `${home}/.config/fish/functions`
  Bun.spawnSync(['mkdir', '-p', dir])
  const content = `function ${name}\n${body}\nend\n`
  await Bun.write(`${dir}/${name}.fish`, content)
}
