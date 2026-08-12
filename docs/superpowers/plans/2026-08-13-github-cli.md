# GitHub CLI 支持实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 rinbake 中新增独立的 `github-cli` 系统模块，支持安装 `gh`、交互式认证以及可重复验证。

**Architecture:** 新模块位于 `src/modules/system/github-cli.ts`，安装通过现有 `aptInstall`，命令检测通过 `hasCommand`。认证通过 `gh auth status --json hosts` 判断状态，并将命令执行、TTY 检测、确认提示抽象为可注入依赖，使核心分支可以在不访问网络、不启动真实登录的情况下测试；真实登录使用继承终端 I/O 的 `gh auth login`。

**Tech Stack:** Bun、TypeScript、`@clack/prompts`、Bun test、现有 rinbake module registry。

---

## 文件变更地图

- Create: `rinbake/src/modules/system/github-cli.ts` — GitHub CLI 模块、认证状态模型、JSON 解析、命令执行适配和配置流程。
- Modify: `rinbake/src/modules/index.ts` — 导入并注册 `github-cli`，使 `init`、`install`、`configure` 自动发现它。
- Modify: `rinbake/test/modules.test.ts` — 模块元数据、认证状态解析、安装分支和配置分支测试。
- Modify: `README.md` — 补充模块表和 `rinbake install/configure github-cli` 用法。

不修改 `src/commands/install.ts`、`src/commands/configure.ts` 或 `installed.json` 管理逻辑：安装成功后的记录仍由现有 `cmdInstall()` 负责，配置流程不改变安装记录。

## 实现约定

- `detect()` 只返回 `hasCommand('gh')`，不检查认证状态。
- `install()` 先检查 `gh`；未安装时调用 `aptInstall('gh')`，若 apt 返回 `false` 或安装后仍检测不到 `gh`，抛出包含 `gh` 的错误。
- 认证状态调用 `gh auth status --json hosts`，不传 `--show-token`。
- 解析器要求顶层存在 `hosts`，并把 hosts 中任意 `state === 'success'` 的 entry 视为已认证；无成功 entry 视为未认证；无效 JSON、缺少 `hosts` 或致命非零命令退出视为状态检查错误。
- `gh auth login` 使用继承 stdin/stdout/stderr 的交互式进程；状态查询使用 pipe 捕获 stdout/stderr。
- 默认依赖通过真实 Bun 进程和现有 UI 函数工作；测试通过依赖对象注入 runner、`isTTY`、confirm 和日志回调，不访问真实认证文件或网络。
- 认证状态输出只显示 `gh auth status --json hosts` 返回的非 token 字段；不调用任何 token 输出命令。

## Task 1: 先写模块注册与纯解析测试

**Files:**
- Modify: `rinbake/test/modules.test.ts`
- Create: `rinbake/src/modules/system/github-cli.ts`（仅添加满足 import 的最小导出骨架，随后在 Task 2 完成）

- [ ] **Step 1: 添加模块注册失败测试**

在现有 `module structure` 测试中增加：

```ts
test('github-cli is enabled and configurable', () => {
  const mod = getModule('github-cli')
  expect(mod).toBeDefined()
  expect(mod!.enabled).toBe(true)
  expect(mod!.category).toBe('system')
  expect(typeof mod!.configure).toBe('function')
})
```

同时在 `module detect functions` 测试中保留统一的 boolean 断言；后续增加对纯解析器的独立测试。

- [ ] **Step 2: 添加认证 JSON 解析的失败测试**

从模块导入 `parseAuthStatus`，覆盖四个行为：

```ts
test('parseAuthStatus recognizes a successful host entry', () => {
  expect(parseAuthStatus(JSON.stringify({ hosts: { 'github.com': [{ state: 'success', login: 'ROLE' }] } }))).toEqual({
    authenticated: true,
  })
})

test('parseAuthStatus treats hosts without success as unauthenticated', () => {
  expect(parseAuthStatus(JSON.stringify({ hosts: { 'github.com': [{ state: 'error' }] } }))).toEqual({
    authenticated: false,
  })
})

test('parseAuthStatus rejects malformed or incomplete output', () => {
  expect(() => parseAuthStatus('{')).toThrow()
  expect(() => parseAuthStatus('{}')).toThrow()
})
```

预期此时测试失败，原因是模块与解析器尚未实现，而不是测试语法错误。

- [ ] **Step 3: 运行失败测试确认 RED**

Run: `cd rinbake && bun test test/modules.test.ts`

Expected: FAIL，失败集中在 `github-cli` 未注册或 `parseAuthStatus` 未定义。

- [ ] **Step 4: Commit 测试基线**

```bash
git add rinbake/test/modules.test.ts
git commit -m "test: define GitHub CLI module and auth parsing behavior"
```

## Task 2: 实现 GitHub CLI 模块和认证依赖边界

**Files:**
- Create: `rinbake/src/modules/system/github-cli.ts`
- Modify: `rinbake/src/modules/index.ts`

- [ ] **Step 1: 实现纯认证状态解析器**

在 `github-cli.ts` 中定义并导出：

```ts
export interface AuthStatus {
  authenticated: boolean
}

export function parseAuthStatus(stdout: string): AuthStatus
```

实现要求：

- `JSON.parse` 失败时抛出带有 `gh auth status` 上下文的错误。
- 顶层 `hosts` 缺失、不是对象或条目不是数组时抛出错误。
- 遍历所有 host entry，只要 entry 的 `state` 精确等于 `success` 就返回 `{ authenticated: true }`。
- 没有成功 entry 时返回 `{ authenticated: false }`。
- 只读取状态字段，不读取或打印 token 字段。

- [ ] **Step 2: 实现可注入的命令执行适配器**

定义模块内部使用的依赖类型，至少包括：

```ts
interface GhResult {
  exitCode: number
  stdout: string
  stderr: string
}

interface GithubCliDeps {
  hasGh: () => Promise<boolean>
  runStatus: () => Promise<GhResult>
  runLogin: () => Promise<GhResult>
  isTTY: () => boolean
  confirmRelogin: () => Promise<boolean | symbol>
  logInfo: (message: string) => void
  logStep: (message: string) => void
  logWarn: (message: string) => void
}
```

默认依赖要求：

- `hasGh` 调用现有 `hasCommand('gh')`。
- `runStatus` 启动 `gh auth status --json hosts`，pipe 捕获 stdout/stderr。
- `runLogin` 启动 `gh auth login`，stdin/stdout/stderr 继承当前终端，等待退出后返回退出码。
- `isTTY` 返回 `Boolean(process.stdin.isTTY)`。
- prompt 和日志分别绑定现有 `confirm`、`logInfo`、`logStep`、`logWarn`。

为测试暴露一个接受依赖的配置入口，例如 `configureGithubCli(deps = defaultDeps)`；模块导出的 `configure()` 只调用默认依赖版本。不要把测试桩写入生产全局状态。

- [ ] **Step 3: 实现安装和检测**

实现标准模块字段：

```ts
export const id = 'github-cli'
export const label = 'GitHub CLI (gh)'
export const description = '安装 GitHub CLI 并完成 GitHub 认证'
export const category = 'system' as const
export const enabled = true
```

`install()` 行为：

1. 已有 `gh` 时输出已安装日志并返回。
2. 未安装时调用 `aptInstall('gh')`。
3. apt 返回失败时抛出 `gh 安装失败` 类错误。
4. apt 成功后再次检查 `hasCommand('gh')`；检查失败时抛出 `gh 安装后未找到` 类错误。
5. 成功时输出完成日志。

`detect()` 直接返回 `hasCommand('gh')`。

- [ ] **Step 4: 实现配置状态机**

`configureGithubCli()` 按以下顺序执行：

1. `hasGh()` 为 false：输出先安装提示并返回。
2. 执行 `runStatus()`；非零退出码直接输出错误并返回，不执行登录。
3. 解析 stdout；解析失败直接输出错误并返回，不执行登录。
4. 已认证：输出 status stdout；TTY 下调用 `confirmRelogin()`，仅返回严格 `true` 时调用 `runLogin()`；其他结果保留现状并返回。非 TTY 直接返回。
5. 未认证：TTY 下调用 `runLogin()`；非 TTY 输出手动命令提示并返回。
6. 登录退出码为 0 时再次执行 status，按同样的非零/解析失败/成功规则验证；验证成功输出完成日志，验证失败输出警告。
7. 登录退出码非 0 时输出警告，不抛出认证流程异常，不修改安装记录。

状态命令失败时将 stderr/stdout 截断为可读摘要用于日志，避免把超长命令输出直接写入终端；不要通过 `gh auth status --show-token` 或 `gh auth token` 获取信息。

- [ ] **Step 5: 注册模块**

在 `rinbake/src/modules/index.ts`：

```ts
import * as githubCli from './system/github-cli'
```

并将 `githubCli` 放入 `modules` 数组的 system 模块区域，保持 `getAllModules()`、`getModule()` 自动可见。

- [ ] **Step 6: 运行 Task 1 测试确认 GREEN**

Run: `cd rinbake && bun test test/modules.test.ts`

Expected: 所有模块注册和认证解析测试 PASS；若失败，修正实现而不是放宽断言。

- [ ] **Step 7: Commit 模块实现**

```bash
git add rinbake/src/modules/system/github-cli.ts rinbake/src/modules/index.ts rinbake/test/modules.test.ts
git commit -m "feat: add GitHub CLI install and auth module"
```

## Task 3: 为安装和配置核心分支补充 TDD 测试

**Files:**
- Modify: `rinbake/test/modules.test.ts`
- Modify: `rinbake/src/modules/system/github-cli.ts`（仅在测试暴露出设计缺口时调整依赖边界）

- [ ] **Step 1: 添加安装分支测试**

将安装逻辑抽成可注入函数或依赖，使测试不调用真实 apt。覆盖：

- `hasGh()` 初始为 true：不调用 apt，返回成功。
- `hasGh()` 初始为 false 且 apt 返回 false：抛出包含 `gh` 的错误。
- apt 返回 true 但安装后 `hasGh()` 仍为 false：抛出包含 `gh` 的错误。
- apt 返回 true 且安装后检测为 true：返回成功。

先运行：`cd rinbake && bun test test/modules.test.ts`

Expected: 新增分支测试在实现注入入口前 FAIL。

- [ ] **Step 2: 实现最小安装依赖入口并使测试通过**

保留导出的模块 `install()` 默认行为不变；仅将 `hasCommand` 和 `aptInstall` 作为可替换依赖传入内部 `installGithubCli()`，让单元测试可以控制调用结果和验证 apt 调用次数。

Run: `cd rinbake && bun test test/modules.test.ts`

Expected: 安装分支测试 PASS，现有测试仍 PASS。

- [ ] **Step 3: 添加配置状态机测试**

使用依赖注入覆盖：

- 未安装：只输出安装提示，不调用 status/login。
- status 非零：输出错误，不调用 login。
- status 无效 JSON：输出错误，不调用 login。
- 已认证 + TTY + 确认 false：不登录。
- 已认证 + TTY + 确认 true：登录后复查 status。
- 未认证 + TTY：调用 login，登录成功后复查 status。
- 未认证 + 非 TTY：不登录，输出 `gh auth login` 提示。
- 登录非零：输出警告，不抛出并结束。
- 登录后复查失败：输出警告。

状态 JSON 固定使用不含 token 的 `hosts` fixtures；断言命令参数/runner 调用次数和日志结果，不断言真实 GitHub 输出。

先运行：`cd rinbake && bun test test/modules.test.ts`

Expected: 新增状态机测试在实现完整分支前 FAIL。

- [ ] **Step 4: 完成最小状态机实现并验证 GREEN**

只实现设计文档规定的分支，不增加 token 输入、GitHub API、repo 操作或顶层命令。

Run: `cd rinbake && bun test test/modules.test.ts`

Expected: 所有单元测试 PASS。

- [ ] **Step 5: Commit 核心分支测试**

```bash
git add rinbake/test/modules.test.ts rinbake/src/modules/system/github-cli.ts
git commit -m "test: cover GitHub CLI install and auth branches"
```

## Task 4: 更新用户文档

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 补充模块表**

在 `git` 附近增加：

```markdown
| `github-cli` | GitHub CLI (`gh`) 安装与认证 |
```

- [ ] **Step 2: 补充 rinbake 使用示例**

在 rinbake 命令表附近增加说明：

```bash
rinbake install github-cli
rinbake configure github-cli
```

并说明 `configure` 会调用 GitHub CLI 原生认证流程，认证信息由 `gh` 管理。

- [ ] **Step 3: 检查文档 diff 并提交**

Run: `git diff --check`

Expected: 无 whitespace 错误。

```bash
git add README.md
git commit -m "docs: document GitHub CLI module"
```

## Task 5: 全量验证与交付检查

**Files:**
- No new files; validate all changed files.

- [ ] **Step 1: 运行单元测试**

Run: `cd rinbake && bun test test/modules.test.ts`

Expected: 测试全部 PASS，且不访问网络、不启动真实 `gh auth login`。

- [ ] **Step 2: 运行 TypeScript 检查**

Run: `cd rinbake && bunx tsc --noEmit`

Expected: 退出码 0，无类型错误。

- [ ] **Step 3: 验证 CLI 帮助包含既有命令未被破坏**

Run: `cd rinbake && bun run src/index.ts --help`

Expected: 正常输出帮助文本，退出码 0；模块选择和配置命令仍可通过 registry 发现 `github-cli`。

- [ ] **Step 4: 检查最终工作区和提交内容**

Run:

```bash
git diff --check
git status --short
git log --oneline -6
```

Expected: 无未预期修改、无 whitespace 错误；提交历史包含模块、测试和文档变更。

- [ ] **Step 5: 按 verification-before-completion 技能复核**

在宣布完成前，重新核对实际命令输出与本计划的验收条件，尤其确认：

- `detect()` 没有被实现为认证检查。
- status 失败不会自动触发 login。
- 非 TTY 不会阻塞。
- 认证 token 未进入 rinbake 日志、配置或测试 fixture。

