import { $ } from 'bun'
import * as fs from 'node:fs'
import * as os from 'node:os'
import color from 'picocolors'
import { intro, outro, select, input, confirm, password, logInfo, logWarn, logStep, isCancelled } from '../utils/ui'

interface SshKeyState {
  keyType: 'ed25519' | 'rsa'
  keyName: string
  keyPath: string
  passphrase: string
  remoteHost: string
  remotePort: string
  remoteUser: string
  hostAlias: string
  skipServer: boolean
  skipClient: boolean
}

function getDefaults(): SshKeyState {
  const hostname = os.hostname()
  const username = process.env.USER || process.env.LOGNAME || 'user'
  const keyName = `${hostname}-${username}`
  return {
    keyType: 'ed25519',
    keyName,
    keyPath: `${process.env.HOME || '/root'}/.ssh/${keyName}`,
    passphrase: '',
    remoteHost: '',
    remotePort: '22',
    remoteUser: '',
    hostAlias: '',
    skipServer: true,
    skipClient: true,
  }
}

export async function cmdSshKey(_args: string[]): Promise<void> {
  intro(color.bgCyan(' rinbake ssh-key '))

  const state = getDefaults()

  // Step 1: Info & confirm
  logStep('1/4: SSH 密钥信息')
  console.log(`  主机:    ${os.hostname()}`)
  console.log(`  用户:    ${state.keyName}`)
  console.log(`  类型:    ${state.keyType}`)
  console.log(`  路径:    ${state.keyPath}`)

  const choices = await select({
    message: '选择操作',
    options: [
      { value: 'confirm', label: '确认并生成密钥' },
      { value: 'modify',  label: '修改密钥名称' },
      { value: 'type',    label: `修改密钥类型 (当前: ${state.keyType})` },
      { value: 'cancel',  label: '取消' },
    ],
  })
  if (isCancelled(choices) || choices === 'cancel') { outro('已取消'); return }

  if (choices === 'modify') {
    const nameInput = await input({ message: '密钥名称', defaultValue: state.keyName })
    if (typeof nameInput === 'string' && nameInput.trim()) {
      state.keyName = nameInput.trim()
      state.keyPath = `${process.env.HOME || '/root'}/.ssh/${state.keyName}`
    }
  } else if (choices === 'type') {
    const typeChoice = await select({
      message: '选择密钥类型',
      options: [
        { value: 'ed25519', label: 'ED25519 (推荐，更安全)' },
        { value: 'rsa',     label: 'RSA 4096 (兼容性更好)' },
      ],
    })
    if (typeof typeChoice === 'string') state.keyType = typeChoice as 'ed25519' | 'rsa'
  }

  // Step 2: Generate key
  logStep('2/4: 生成密钥')
  if (fs.existsSync(state.keyPath)) {
    logWarn(`密钥已存在: ${state.keyPath}`)
    const overwrite = await confirm({ message: '覆盖？', defaultValue: false })
    if (overwrite !== true) { outro('跳过'); return }
  }

  const setPass = await confirm({ message: '设置密码保护？', defaultValue: false })
  if (setPass === true) {
    const p1 = await password({ message: '密码:' })
    const p2 = await password({ message: '确认密码:' })
    if (typeof p1 === 'string' && typeof p2 === 'string' && p1 === p2 && p1.trim()) {
      state.passphrase = p1
    } else {
      logWarn('密码不匹配或为空，跳过密码保护')
    }
  }

  await $`mkdir -p ${process.env.HOME || '/root'}/.ssh`.nothrow()
  const bits = state.keyType === 'rsa' ? '-b 4096' : ''
  const passOpt = state.passphrase ? `-N "${state.passphrase}"` : '-N ""'
  await $`ssh-keygen -t ${state.keyType} ${bits} -f ${state.keyPath} -C ${state.keyName} ${passOpt} -q`.nothrow()
  await $`chmod 600 ${state.keyPath}`.nothrow()
  await $`chmod 644 ${state.keyPath}.pub`.nothrow()
  logInfo(`密钥生成成功: ${state.keyPath}`)

  // Step 3: Remote server
  logStep('3/4: 配置远程服务器')
  const doServer = await confirm({ message: '将公钥复制到远程服务器？', defaultValue: false })
  if (doServer === true) {
    const host = await input({ message: '服务器地址 (IP/域名)' })
    if (typeof host === 'string' && host.trim()) state.remoteHost = host.trim()

    const port = await input({ message: 'SSH 端口', defaultValue: '22' })
    if (typeof port === 'string' && port.trim()) state.remotePort = port.trim()

    const user = await input({ message: '远程用户名' })
    if (typeof user === 'string' && user.trim()) state.remoteUser = user.trim()

    if (state.remoteHost && state.remoteUser) {
      const result = await $`ssh-copy-id -i ${state.keyPath}.pub -p ${state.remotePort} ${state.remoteUser}@${state.remoteHost}`.nothrow()
      if (result.exitCode === 0) {
        logInfo('公钥复制成功')
        state.skipServer = false
      } else {
        logWarn('公钥复制失败，检查连接信息')
      }
    }
  }

  // Step 4: SSH config
  logStep('4/4: 配置 SSH 客户端')
  if (!state.skipServer) {
    const doClient = await confirm({ message: '添加 Host 配置到 ~/.ssh/config？', defaultValue: true })
    if (doClient === true) {
      const alias = await input({ message: 'Host 别名', defaultValue: state.remoteHost })
      if (typeof alias === 'string' && alias.trim()) state.hostAlias = alias.trim()

      const sshConfigPath = `${process.env.HOME || '/root'}/.ssh/config`
      let config = ''
      if (fs.existsSync(sshConfigPath)) config = fs.readFileSync(sshConfigPath, 'utf-8')

      const hostRe = new RegExp(`^Host ${state.hostAlias}$`, 'm')
      if (hostRe.test(config)) {
        const replace = await confirm({ message: `Host '${state.hostAlias}' 已存在，覆盖？`, defaultValue: false })
        if (replace === true) {
          config = config.replace(new RegExp(`^Host ${state.hostAlias}[\\s\\S]*?^\\w`, 'm'), '')
        }
      }

      const entry = `
# Added by rinbake on ${new Date().toISOString().slice(0, 10)}
Host ${state.hostAlias}
    HostName ${state.remoteHost}
    User ${state.remoteUser}
    Port ${state.remotePort}
    IdentityFile ${state.keyPath}
`
      fs.appendFileSync(sshConfigPath, entry)
      await $`chmod 600 ${sshConfigPath}`.nothrow()
      logInfo(`SSH config 已添加: Host ${state.hostAlias}`)
      state.skipClient = false
    }
  }

  // Summary
  console.log('')
  logInfo('=== SSH 密钥设置完成 ===')
  console.log(`  密钥:  ${state.keyPath}`)
  console.log(`  公钥:  ${state.keyPath}.pub`)
  if (!state.skipServer) console.log(`  服务器: ${state.remoteUser}@${state.remoteHost}:${state.remotePort}`)
  if (!state.skipClient) console.log(`  连接:   ssh ${state.hostAlias}`)
  console.log('')
  const pubkey = fs.readFileSync(`${state.keyPath}.pub`, 'utf-8').trim()
  logInfo(`公钥内容:\n${pubkey}`)
  outro('完成')
}
