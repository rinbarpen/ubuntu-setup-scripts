#!/usr/bin/env bun
import color from 'picocolors'
import { cmdInit } from './commands/init'
import { cmdInstall } from './commands/install'
import { cmdConfigure } from './commands/configure'
import { cmdKeys } from './commands/keys'
import { cmdMcp } from './commands/mcp'
import { cmdStatus } from './commands/status'

const help = `
${color.bold('rinbake')} — Ubuntu 开发环境一站式安装配置工具

${color.underline('用法')}:
  ${color.cyan('rinbake init')}                   交互式安装向导
  ${color.cyan('rinbake install [module...]')}    安装模块（可指定多个）
  ${color.cyan('rinbake install --all')}          安装全部模块
  ${color.cyan('rinbake configure [module...]')}  配置模块
  ${color.cyan('rinbake keys')}                   API Key 管理
  ${color.cyan('rinbake keys list')}              列出所有 keys
  ${color.cyan('rinbake keys set <NAME>')}        设置 key
  ${color.cyan('rinbake mcp')}                    MCP 服务器管理
  ${color.cyan('rinbake mcp list')}               列出 MCP 服务器
  ${color.cyan('rinbake mcp install <name...>')}  启用 MCP 服务器
  ${color.cyan('rinbake status')}                 查看安装状态
  ${color.cyan('rinbake help')}                   显示帮助

${color.dim('配置目录: ~/.config/rinbake/')}
${color.dim('API Keys:  ~/.config/rinbake/keys.env')}
`

async function main(): Promise<void> {
  const args = process.argv.slice(2)
  const cmd = args[0] || 'help'

  switch (cmd) {
    case 'init':
      await cmdInit()
      break
    case 'install':
      await cmdInstall(args.slice(1))
      break
    case 'configure':
    case 'config':
      await cmdConfigure(args.slice(1))
      break
    case 'keys':
    case 'key':
      await cmdKeys(args.slice(1))
      break
    case 'mcp':
      await cmdMcp(args.slice(1))
      break
    case 'status':
    case 'st':
    case 'doctor':
      await cmdStatus()
      break
    case 'help':
    case '-h':
    case '--help':
    default:
      console.log(help)
      break
  }
}

main().catch(err => {
  console.error(color.red('错误:'), err)
  process.exit(1)
})
