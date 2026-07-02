import { $ } from 'bun'
import { logStep, logInfo, multiselect, input } from '../utils/ui'

export const id = 'skills'
export const label = 'Skills (外部技能集)'
export const description = '安装外部 skill 集合到 ~/.claude/skills/'
export const category = 'other' as const
export const enabled = false

export async function install(): Promise<void> {
  const skillsTarget = `${process.env.HOME || '/root'}/.claude/skills`
  await $`mkdir -p ${skillsTarget}`.nothrow()

  const selection = await multiselect({
    message: '选择要安装的 skills',
    options: [
      { value: 'superpowers', label: '核心 superpowers 技能系统', hint: 'git' },
      { value: 'ui-ux', label: 'UI/UX Pro Max 设计技能', hint: 'git' },
      { value: 'ai-research', label: 'AI 自动调研', hint: 'git' },
      { value: 'anthropic-skills', label: 'Anthropic 官方技能集', hint: 'git' },
    ],
    required: false,
  })

  const selected = Array.isArray(selection)
    ? selection.filter((v): v is string => typeof v === 'string')
    : []

  for (const skill of selected) {
    const url = await input({ message: `${skill} 仓库 URL` })
    if (typeof url !== 'string' || !url.trim()) {
      logStep(`跳过 ${skill}`)
      continue
    }
    const dest = `${skillsTarget}/${skill}`
    if (await Bun.file(`${dest}/.git`).exists()) {
      logStep(`更新 ${skill}...`)
      await $`git -C ${dest} pull --ff-only`.nothrow()
    } else {
      logStep(`安装 ${skill}...`)
      await $`git clone ${url.trim()} ${dest}`.nothrow()
    }
    logInfo(`Skill installed: ${skill}`)
  }

  logInfo('skills: 完成')
}

export async function detect(): Promise<boolean> {
  const skillsTarget = `${process.env.HOME || '/root'}/.claude/skills`
  try {
    const proc = Bun.spawnSync(['ls', '-A', skillsTarget])
    return proc.exitCode === 0 && proc.stdout.toString().trim().length > 0
  } catch {
    return false
  }
}
