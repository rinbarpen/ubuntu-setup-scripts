import { $ } from 'bun'
import * as fs from 'node:fs'
import color from 'picocolors'
import { intro, outro, input, confirm, logInfo, logWarn, logStep, isCancelled } from '../utils/ui'

interface UserState {
  username: string
  pubkey: string
  sshPort: string
  sftpPort: string
}

export async function cmdCreateUser(_args: string[]): Promise<void> {
  const euid = process.getuid?.() ?? 0
  if (euid !== 0) {
    logWarn('需要 root 权限，请用 sudo 运行')
    console.log('  sudo rinbake create-user')
    return
  }

  intro(color.bgCyan(' rinbake create-user '))
  console.log('  创建支持 SSH/FTP/SFTP 的用户')
  console.log('  端口: SSH=2345, FTP/SFTP=8021')
  console.log('')

  const state: UserState = { username: '', pubkey: '', sshPort: '2345', sftpPort: '8021' }

  // Step 1: Username
  logStep('1/5: 用户名')
  while (true) {
    const name = await input({ message: '用户名' })
    if (isCancelled(name)) { outro('已取消'); return }
    if (typeof name !== 'string' || !name.trim()) { logWarn('用户名不能为空'); continue }
    if (!/^[a-z_][a-z0-9_-]*[$]?$/.test(name)) { logWarn('格式无效（仅小写字母、数字、下划线）'); continue }

    const exists = await $`id ${name} 2>/dev/null`.nothrow()
    if (exists.exitCode === 0) {
      const overwrite = await confirm({ message: `用户 ${name} 已存在，覆盖配置？`, defaultValue: false })
      if (overwrite !== true) continue
    }
    state.username = name
    break
  }

  // Step 2: SSH public key
  logStep('2/5: SSH 公钥（可选）')
  const pk = await input({ message: '粘贴公钥（留空跳过）' })
  if (typeof pk === 'string' && pk.trim()) {
    if (/^(ssh-ed25519|ssh-rsa|ssh-dss|ecdsa-sha2)/.test(pk.trim())) {
      state.pubkey = pk.trim()
      logInfo('格式验证通过')
    } else {
      const force = await confirm({ message: '格式不识别，仍保存？', defaultValue: false })
      if (force === true) state.pubkey = pk.trim()
    }
  }

  // Step 3: SSH port
  logStep('3/5: SSH 端口')
  const sshPort = await input({ message: 'SSH 端口', defaultValue: '2345' })
  if (typeof sshPort === 'string' && sshPort.trim()) {
    const p = parseInt(sshPort, 10)
    if (p >= 1 && p <= 65535) state.sshPort = sshPort.trim()
    else logWarn('端口无效，使用默认 2345')
  }

  // Step 4: FTP port
  logStep('4/5: FTP/SFTP 端口')
  const sftpPort = await input({ message: 'FTP 端口', defaultValue: '8021' })
  if (typeof sftpPort === 'string' && sftpPort.trim()) {
    const p = parseInt(sftpPort, 10)
    if (p >= 1 && p <= 65535) state.sftpPort = sftpPort.trim()
    else logWarn('端口无效，使用默认 8021')
  }

  // Step 5: Confirm
  logStep('5/5: 确认')
  console.log('')
  console.log('  配置摘要:')
  console.log(`    用户名:  ${state.username}`)
  console.log(`    SSH 端口: ${state.sshPort}`)
  console.log(`    FTP 端口: ${state.sftpPort}`)
  console.log(`    公钥:     ${state.pubkey ? '已设置' : '未设置'}`)
  console.log('')

  const proceed = await confirm({ message: '确认执行？', defaultValue: true })
  if (proceed !== true) { outro('已取消'); return }

  // Execute
  logStep('执行: 创建用户')

  // 1. Create user
  const userExists = await $`id ${state.username} 2>/dev/null`.nothrow()
  if (userExists.exitCode !== 0) {
    const r1 = await $`useradd -m -s /sbin/nologin ${state.username} 2>/dev/null`.nothrow()
    if (r1.exitCode !== 0) await $`useradd -m -s /usr/sbin/nologin ${state.username}`.nothrow()
    logInfo('用户已创建')
  } else {
    logInfo('用户已存在')
  }

  // 2. SSH key
  if (state.pubkey) {
    const userInfo = (await $`getent passwd ${state.username}`).stdout.toString().trim()
    const userHome = userInfo.split(':')[5] || `/home/${state.username}`
    await $`mkdir -p ${userHome}/.ssh`.nothrow()
    await $`chmod 700 ${userHome}/.ssh`.nothrow()
    fs.writeFileSync(`${userHome}/.ssh/authorized_keys`, state.pubkey + '\n')
    await $`chmod 600 ${userHome}/.ssh/authorized_keys`.nothrow()
    await $`chown ${state.username}:${state.username} ${userHome}/.ssh/authorized_keys`.nothrow()
    logInfo('公钥已配置')
  }

  // 3. SSH config
  const sshdConfig = `/etc/ssh/sshd_config.d/custom.conf`
  await $`mkdir -p /etc/ssh/sshd_config.d`.nothrow()
  if (!fs.existsSync(sshdConfig) || !fs.readFileSync(sshdConfig, 'utf-8').includes(`Port ${state.sshPort}`)) {
    const sshConfigContent = `Port ${state.sshPort}
ListenAddress 0.0.0.0
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
Subsystem sftp internal-sftp
`
    fs.writeFileSync(sshdConfig, sshConfigContent)
    logInfo(`SSH 配置已写入 ${sshdConfig}`)
  }
  await $`systemctl reload sshd`.nothrow()

  // 4. FTP
  const vsftpdConfig = `/etc/vsftpd.custom.conf`
  const sftpPortNum = parseInt(state.sftpPort, 10)
  if (fs.existsSync(vsftpdConfig)) fs.rmSync(vsftpdConfig)
  const vsftpdContent = `listen=${sftpPortNum}
listen_address=0.0.0.0
pasv_enable=YES
pasv_min_port=${sftpPortNum + 1000}
pasv_max_port=${sftpPortNum + 1010}
pasv_address=127.0.0.1
allow_writeable_chroot=YES
chroot_local_user=YES
secure_chroot_dir=/var/run/vsftpd/empty
local_enable=YES
local_umask=022
write_enable=YES
xferlog_enable=YES
xferlog_file=/var/log/vsftpd.log
connect_from_port_20=NO
background=YES
listen_mode=standalone
`
  fs.writeFileSync(vsftpdConfig, vsftpdContent)
  await $`mkdir -p /var/run/vsftpd/empty`.nothrow()
  await $`pkill vsftpd 2>/dev/null`.nothrow()
  await new Promise(r => setTimeout(r, 500))
  await $`vsftpd ${vsftpdConfig} &`.nothrow()

  logInfo('FTP 服务已配置')

  const hostname = (await $`hostname`).stdout.toString().trim()
  console.log('')
  logInfo('=== 用户创建完成 ===')
  console.log('')
  console.log('  连接信息:')
  console.log(`    SSH:  ssh -p ${state.sshPort} ${state.username}@<服务器IP>`)
  console.log(`    SFTP: sftp -P ${state.sftpPort} ${state.username}@<服务器IP>`)
  console.log(`    FTP:  ftp -p ${state.sftpPort} <服务器IP>`)
  console.log('')
  logInfo('注意: FTP 需设置密码或使用公钥认证')
  outro('完成')
}
