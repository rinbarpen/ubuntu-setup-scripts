# GitHub CLI 支持设计

## 背景

rinbake 已通过模块注册表统一管理 Ubuntu 开发环境组件，并通过 `install` 与
`configure` 命令分别处理安装和配置。本功能为 rinbake 增加 GitHub CLI (`gh`)
支持，使用户可以在现有模块流程中安装 GitHub CLI 并完成 GitHub 认证。

## 目标

- 提供独立的 `github-cli` 系统模块。
- 支持 `rinbake install github-cli` 安装 `gh`。
- 支持 `rinbake configure github-cli` 交互式执行 `gh auth login`。
- 安装和配置操作可重复执行。
- 不由 rinbake 保存、解析或复制 GitHub token。
- 不影响现有 Git 模块的职责和行为。

## 非目标

- 不新增顶层 `rinbake github` 命令。
- 不实现 GitHub API 封装、仓库管理或 PR 操作。
- 不在测试中执行真实 GitHub 登录或访问网络。
- 不将 GitHub 认证信息迁移到 rinbake 配置目录。

## 模块设计

新增 `rinbake/src/modules/system/github-cli.ts`，导出标准模块字段：

- `id = 'github-cli'`
- GitHub CLI 相关的中文 `label` 与 `description`
- `category = 'system'`
- `enabled = true`
- `install()`、`configure()` 和 `detect()`

`detect()` 的语义固定为“当前 PATH 中是否存在 `gh` 命令”，只表示安装状态，
不表示 GitHub 是否已认证。

在 `rinbake/src/modules/index.ts` 中导入并注册该模块。注册后，现有的
`rinbake init`、`rinbake install` 和 `rinbake configure` 流程会自动发现它。

### 安装

`install()` 使用现有 `hasCommand` 检查 `gh`：

1. 如果 `gh` 已存在，记录已安装并跳过安装。
2. 如果不存在，调用现有 `aptInstall('gh')`。
3. 安装后再次检查 `gh`；如果仍不存在，则抛出错误，让上层安装命令将模块标记为失败。

该实现沿用当前系统模块的 Ubuntu apt 安装约定，不修改 apt 源，也不下载额外安装脚本。

### 认证配置

`configure()` 不自行管理凭据，只调用 GitHub CLI 的认证命令：

1. 如果 `gh` 未安装，输出提示并结束，不启动认证流程。
2. 执行 `gh auth status --json hosts` 检查当前认证状态，不使用 `--show-token`。
3. 解析 JSON 中 `hosts` 的认证条目：存在 `state = "success"` 的条目表示已认证；没有成功条目表示需要认证。
4. 如果状态命令返回致命错误或 JSON 无法解析，输出错误并结束，不把异常误判为未认证。
5. 如果已认证，显示 host/account 状态；TTY 环境下询问是否重新登录，默认不重新登录。非 TTY 环境直接保留现有状态。
6. 如果未认证且有 TTY，启动交互式 `gh auth login`，保留 GitHub CLI 原生的协议、浏览器和设备码选项。
7. 如果未认证且无 TTY，不启动交互登录，只提示用户手动执行 `gh auth login`。
8. 登录返回后再次执行 JSON 状态检查；存在成功条目时输出完成信息，否则输出警告。

认证状态、token 和 GitHub CLI 配置全部由 `gh` 按其默认机制管理，rinbake 不读写这些内容。

## 错误处理

- apt 安装失败或安装后找不到 `gh`：抛出包含命令名的错误。
- `gh auth status --json hosts` 没有成功认证条目：进入登录流程，而不是把状态误报为异常。
- `gh auth status --json hosts` 返回非零、输出无法解析或缺少 `hosts` 字段：视为状态检查异常，输出原始错误摘要并结束，不启动登录。
- 用户取消重新登录：保留已有认证状态并正常结束。
- 登录失败或用户取消：输出警告，不写入 `installed.json` 以外的 rinbake 配置；安装成功仍可被记录为已安装。
- 无 TTY：输出可复制的手动认证命令，不阻塞等待输入。

`installed.json` 只由现有 `cmdInstall()` 在 `install()` 成功返回后维护；
`configure()` 不写入或删除安装记录。

## 测试与验收

新增或补充单元测试，至少验证：

- `github-cli` 已注册且模块 ID 唯一。
- 模块元数据正确，包含 `configure` 函数。
- `detect()` 返回布尔值，并明确表示命令安装状态而非认证状态。
- 认证状态解析覆盖：成功认证、无成功条目、命令致命错误和无效 JSON。
- 配置流程覆盖：已认证且保留、TTY 重新登录、未认证登录、非 TTY 提示手动登录。
- 安装失败不会被标记为成功，配置失败不会改变 `installed.json`。
- 模块注册测试仍通过全部现有模块。

不在自动化测试中调用真实 apt、`gh auth login`、网络或用户认证文件。

状态检查依赖 GitHub CLI 的机器可读 `gh auth status --json hosts` 输出；
该命令在认证问题时仍返回 JSON，只有致命错误才通过非零退出码报告，避免将
网络或 CLI 错误误判为“未登录”。

验收命令：

```bash
cd rinbake
bun test test/modules.test.ts
bunx tsc --noEmit
```

文档方面，在根目录 README 的模块和 rinbake 命令说明中补充：

```bash
rinbake install github-cli
rinbake configure github-cli
```
