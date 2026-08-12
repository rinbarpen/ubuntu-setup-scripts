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

- `detect()` 遵循现有 `ModuleDefinition.detect?: () => Promise<boolean>` 异步接口，只返回 `hasCommand('gh')`，不检查认证状态；导出的 `detectGithubCli(hasGh)` 纯粹转发异步命令检测结果，供测试证明认证状态不会影响 detect。
- `install()` 先检查 `gh`；未安装时调用 `aptInstall('gh')`，若 apt 返回 `false` 或安装后仍检测不到 `gh`，抛出包含 `gh` 的错误。
- 认证状态调用 `gh auth status --json hosts`，不传 `--show-token`。
- 解析器要求顶层存在 `hosts`，并把 hosts 中任意 `state === 'success'` 的 entry 视为已认证；无成功 entry 视为未认证；无效 JSON、缺少 `hosts` 或致命非零命令退出视为状态检查错误。
- `gh auth login` 使用继承 stdin/stdout/stderr 的交互式进程；状态查询使用 pipe 捕获 stdout/stderr。
- 默认依赖通过真实 Bun 进程和现有 UI 函数工作；测试通过依赖对象注入 runner、`isTTY`、confirm 和日志回调，不访问真实认证文件或网络。
- 认证状态输出只显示 `gh auth status --json hosts` 返回的非 token 字段；不调用任何 token 输出命令。

## Task 1: 先写模块注册与纯解析测试

**Files:**
- Modify: `rinbake/test/modules.test.ts`

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

同时在 `module detect functions` 测试中对每个检测器使用 `const result = await m.detect()` 后再断言 `typeof result === 'boolean'`；后续增加对纯解析器的独立测试。

- [ ] **Step 2: 添加认证 JSON 解析的失败测试**

从模块导入 `parseAuthStatus` 和 `detectGithubCli`，覆盖解析器四个行为，并验证 `await detectGithubCli(async () => true)` 与 `await detectGithubCli(async () => false)` 分别返回 true/false，不依赖认证 JSON。现有 `all modules are unique` 测试继续作为 `github-cli` 注册后的 ID 唯一性验收；另在本测试块断言 `getModule('github-cli')` 返回的 id 正确。

```ts
test('parseAuthStatus recognizes a successful host entry', () => {
  expect(parseAuthStatus(JSON.stringify({ hosts: { 'github.com': [{ state: 'success', host: 'github.com', login: 'ROLE', token: 'TOKEN' }] } }))).toEqual({
    authenticated: true,
    entries: [{ host: 'github.com', login: 'ROLE', state: 'success' }],
  })
})

test('parseAuthStatus treats hosts without success as unauthenticated', () => {
  expect(parseAuthStatus(JSON.stringify({ hosts: { 'github.com': [{ state: 'error' }] } }))).toEqual({
    authenticated: false,
    entries: [{ host: 'github.com', login: '', state: 'error' }],
  })
})

test('parseAuthStatus rejects malformed or incomplete output', () => {
  expect(() => parseAuthStatus('{')).toThrow()
  expect(() => parseAuthStatus('{}')).toThrow()
})
```

预期此时测试失败，原因是模块与解析器尚未实现，而不是测试语法错误。

- [ ] **Step 3: 添加安装和配置状态机失败测试**

使用可注入安装入口覆盖：已安装跳过 apt；apt 返回 `false`；apt 抛异常；apt 成功但安装后仍不可检测；apt 成功且安装后检测成功。断言 apt 调用次数、错误包含 `gh`，以及成功分支返回。

使用依赖注入覆盖：未安装只提示且不调用 status/login；status 非零或抛异常不登录；无效 JSON 不登录；已认证 TTY 下使用默认值 `false` 且不登录；已认证 TTY 下 confirm 返回取消 `symbol` 且不登录；已认证确认 `true` 时调用 `runGh(['auth', 'login'], true)`；未认证 TTY 登录并复查；未认证非 TTY 输出 `gh auth login` 提示且不登录；登录非零输出警告；登录后复查失败输出警告。

状态 fixture 至少包含一个额外的 `token: 'TOKEN'` 哨兵字段，且使用 `hosts` 映射键 `github.com` 与 entry 中显式 `host: 'github.com'` 的完整形态；另测试缺失 login 时归一化为空字符串。断言日志不包含原始 JSON 或 `TOKEN` 字段。另增加：配置失败前后 `readInstalled()` 结果相同，证明配置流程不维护 `installed.json`。

- [ ] **Step 4: 运行失败测试确认 RED**

Run: `cd rinbake && bun test test/modules.test.ts`

Expected: FAIL，失败集中在 `github-cli` 未注册、解析器未定义或安装/认证依赖入口未实现。

- [ ] **Step 5: Commit 测试基线**

```bash
git add rinbake/test/modules.test.ts
git commit -m "test: define GitHub CLI module and auth parsing behavior"
```

## Task 2: 实现模块、安装和认证状态机（GREEN）

**Files:**
- Create: `rinbake/src/modules/system/github-cli.ts`
- Modify: `rinbake/src/modules/index.ts`

- [ ] **Step 1: 实现认证状态模型和解析器**

定义并导出：

```ts
export interface AuthStatusEntry {
  host: string
  login: string
  state: string
}

export interface AuthStatus {
  authenticated: boolean
  entries: AuthStatusEntry[]
}

export async function detectGithubCli(hasGh: () => Promise<boolean>): Promise<boolean>
export function parseAuthStatus(stdout: string): AuthStatus
```

`JSON.parse` 失败、顶层 `hosts` 缺失/为 null/数组/非对象、host value 不是数组或 entry 为 null/数组/非对象时抛出带 `gh auth status` 上下文的错误。对每个 host map entry：优先使用 entry.host 的字符串值，否则使用 map key 作为 host；login 缺失或非字符串时归一化为 `''`；state 必须是字符串，否则抛错。遍历所有 host entry；任一 state 为 `success` 则 authenticated 为 true。不得读取或打印 token。

- [ ] **Step 2: 实现可注入的命令和 UI 依赖**

定义内部依赖类型：

```ts
interface GhResult { exitCode: number; stdout: string; stderr: string }
interface GithubCliDeps {
  hasGh: () => Promise<boolean>
  installGh: (packageName: string) => Promise<boolean>
  runGh: (args: string[], interactive?: boolean) => Promise<GhResult>
  isTTY: () => boolean
  confirmRelogin: () => Promise<boolean | symbol>
  logInfo: (message: string) => void
  logStep: (message: string) => void
  logWarn: (message: string) => void
}
```

默认实现绑定 `hasCommand('gh')`、`aptInstall(packageName)`、现有 UI 函数和 `Boolean(process.stdin.isTTY)`；安装流程必须调用 `installGh('gh')`，测试断言传入包名精确为 `gh`。状态查询调用 `runGh(['auth', 'status', '--json', 'hosts'])` 并 pipe 输出；登录调用 `runGh(['auth', 'login'], true)` 并继承三路终端 I/O。默认 `confirmRelogin` 调用现有 `confirm`，消息明确询问是否重新登录且 `defaultValue: false`。进程启动/等待异常统一转成包含命令名的失败结果或错误，由上层状态机处理。

为测试导出 `installGithubCli(deps)` 与 `configureGithubCli(deps)`；测试通过注入的 `runGh(args, interactive)` 直接断言命令参数和交互标志。模块导出的 `install()`、`configure()` 调用默认依赖版本。测试桩只能通过参数注入，不使用全局 monkey patch。

- [ ] **Step 3: 实现安装和检测**

实现标准字段：

```ts
export const id = 'github-cli'
export const label = 'GitHub CLI (gh)'
export const description = '安装 GitHub CLI 并完成 GitHub 认证'
export const category = 'system' as const
export const enabled = true
```

`installGithubCli()`：已检测到 `gh` 时输出已安装日志并返回；否则执行 `installGh('gh')`，若返回 false 或抛异常则抛出包含 `gh` 的错误；安装成功后再次调用 `hasGh()`，失败则抛出安装后未找到错误；成功输出完成日志。`detectGithubCli()` 接收并转发 `() => Promise<boolean>`；模块 `detect()` 通过 `detectGithubCli(() => hasCommand('gh'))` 实现，`hasCommand('gh')` 本身返回 Promise，认证 JSON 不参与检测。

- [ ] **Step 4: 实现配置状态机**

`configureGithubCli()` 顺序固定为：

1. `hasGh()` 为 false：输出安装提示并返回。
2. 执行 `runGh(['auth', 'status', '--json', 'hosts'])`；非零退出或执行抛错只输出状态检查错误并返回，不登录。
3. 调用 `parseAuthStatus()`；解析异常只输出错误并返回，不登录。
4. 已认证时输出格式化的 host/login/state 摘要，不输出原始 JSON、token 字段或 token 值。TTY 下调用 `confirmRelogin()`，默认值由默认依赖固定为 `false`；只有严格返回 `true` 才登录。非 TTY 直接保留现状。
5. 未认证时，TTY 调用 `runGh(['auth', 'login'], true)`；非 TTY 输出手动 `gh auth login` 提示并返回。
6. 登录退出码为 0 时再次执行 `runGh(['auth', 'status', '--json', 'hosts'])` 并解析；存在成功 entry 输出完成日志，否则输出警告。复查异常、非零或无效 JSON 都只输出警告并返回。
7. 登录退出码非 0 或抛错时输出警告并返回，不更新 `installed.json`。

所有日志均使用固定上下文或脱敏状态摘要，不直接拼接原始 stdout/stderr；错误摘要限制长度且不使用 token 命令。

- [ ] **Step 5: 注册模块**

在 `rinbake/src/modules/index.ts` 导入：

```ts
import * as githubCli from './system/github-cli'
```

并将 `githubCli` 放入 system 模块数组。

- [ ] **Step 6: 运行 GREEN 测试**

Run: `cd rinbake && bun test test/modules.test.ts`

Expected: 所有模块、解析器、安装和认证状态机测试 PASS，不访问网络、不启动真实登录。

- [ ] **Step 7: 提交模块实现**

```bash
git add rinbake/src/modules/system/github-cli.ts rinbake/src/modules/index.ts rinbake/test/modules.test.ts
git commit -m "feat: add GitHub CLI install and auth module"
```

## Task 3: 更新用户文档

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 补充模块表**

在 `git` 附近增加：

```markdown
| `github-cli` | GitHub CLI (`gh`) 安装与认证 |
```

- [ ] **Step 2: 补充 rinbake 使用示例**

在 rinbake 命令说明附近增加：

```bash
rinbake install github-cli
rinbake configure github-cli
```

说明 `configure` 调用 GitHub CLI 原生认证流程，认证信息由 `gh` 管理。

- [ ] **Step 3: 检查并提交文档**

Run: `git diff --check`

Expected: 无 whitespace 错误。

```bash
git add README.md
git commit -m "docs: document GitHub CLI module"
```

## Task 4: 全量验证与交付检查

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

