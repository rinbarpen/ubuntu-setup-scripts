import color from 'picocolors'
import { intro, outro, select, logInfo, logWarn, isCancelled, multiselect } from '../utils/ui'
import { getAllMcpIds, getMcpDef, getMcpServers } from '../modules/mcp'
import { readMcpConfig, writeMcpConfig } from '../config/manager'

export async function cmdMcp(args: string[]): Promise<void> {
  if (args[0] === 'list' || args[0] === 'ls') {
    await listMcp()
  } else if (args[0] === 'install' && args[1]) {
    await installMcp(args.slice(1))
  } else {
    await mcpInteractive()
  }
}

async function listMcp(): Promise<void> {
  intro(color.bgCyan(' rinbake mcp list '))

  const allIds = getAllMcpIds()
  const config = await readMcpConfig()

  logInfo(`${allIds.length} 个可用 MCP 服务器:`)
  for (const id of allIds) {
    const def = getMcpDef(id)
    const enabled = config[id] !== false
    const status = enabled ? color.green('✓') : color.dim('✗')
    logInfo(`  ${status} ${id}: ${def?.command || '?'}`)
  }

  outro('完成')
}

async function installMcp(ids: string[]): Promise<void> {
  intro(color.bgCyan(' rinbake mcp install '))
  const config = await readMcpConfig()

  for (const id of ids) {
    const def = getMcpDef(id)
    if (!def) {
      logWarn(`未知 MCP: ${id}`)
      continue
    }
    config[id] = true
    logInfo(`${id}: 已启用`)
  }

  await writeMcpConfig(config)
  outro('完成')
}

async function mcpInteractive(): Promise<void> {
  intro(color.bgCyan(' rinbake mcp '))

  const action = await select({
    message: 'MCP 服务器管理',
    options: [
      { value: 'list', label: '列出 MCP 服务器' },
      { value: 'toggle', label: '启用/禁用 MCP 服务器' },
    ],
  })

  if (isCancelled(action)) {
    outro('已取消')
    return
  }

  if (action === 'list') {
    await listMcp()
  } else {
    await toggleMcp()
  }
}

async function toggleMcp(): Promise<void> {
  const allIds = getAllMcpIds()
  const config = await readMcpConfig()

  const options = allIds.map(id => ({
    value: id,
    label: id,
    hint: getMcpDef(id)?.command || '',
    checked: config[id] !== false,
  }))

  const result = await multiselect({
    message: '切换 MCP 服务器启用状态（Space 切换）',
    options,
    required: false,
  })

  if (isCancelled(result)) {
    outro('已取消')
    return
  }

  const selected = Array.isArray(result)
    ? result.filter((v): v is string => typeof v === 'string')
    : []

  for (const id of allIds) {
    config[id] = selected.includes(id)
  }

  await writeMcpConfig(config)
  logInfo('MCP 状态已更新')
  outro('完成')
}
