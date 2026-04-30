# 开发进程菜单栏 App 设计规格

## 目标

构建一个个人使用的原生 macOS 菜单栏 App，用来查看并控制开发过程中由 Claude Code、Codex、VS Code、Terminal 以及命令行工具启动的后台进程。App 需要同时显示有监听端口的 dev server，以及没有端口的脚本、worker、MCP server 等进程。

## 非目标

- 不做商业级来源识别，不追求覆盖 Cursor、Warp、iTerm、JetBrains 等所有工具。
- 不做系统清理软件，不扫描或推荐清理系统缓存、登录项、垃圾文件。
- 不默认一键杀整组进程，所有生命周期操作都基于用户手动勾选。
- 不接入 Claude Code、Codex、VS Code 的私有数据库或内部会话协议，第一版只使用 macOS 进程信息推断。

## 技术方向

- App 类型：纯 Swift 原生 macOS 菜单栏 App。
- UI：SwiftUI + AppKit `NSStatusItem` + `NSPopover`。
- 进程采集：优先使用 macOS 系统 API 获取 PID、PPID、进程名、参数、用户、运行时间；必要时通过 `/bin/ps`、`/usr/sbin/lsof` 补充命令行、cwd、监听端口信息。
- 权限范围：只显示当前用户拥有的开发相关进程；不需要管理员权限作为第一版要求。
- 刷新策略：打开 popover 时刷新一次，打开期间每 3 秒刷新一次，用户也可以手动刷新。

## UI 结构

菜单栏点击后展开一个紧凑 popover，不打开主窗口。默认使用浅色 macOS 视觉风格，中文界面为主，无法自然翻译的技术名词保持英文。

顶部区域：

- 标题：`开发进程`
- 状态摘要：例如 `42 个进程 · 已选 9 个`
- 刷新图标按钮
- 视图切换：`来源` / `项目`
- 搜索框：`搜索进程、端口或项目`

主内容区域：

- 使用可展开的树形列表。
- 默认视图为 `来源`，分组顺序为 `Claude Code`、`Codex`、`VS Code`、`Terminal`、`Unknown`。
- 每个来源下按项目分组。
- 每个项目下显示进程节点。
- 进程节点包含复选框、层级缩进、命令摘要、端口、PID、运行时长、类型标签、安全标签。

底部操作栏：

- `停止所选`：对已勾选进程发送 `SIGTERM`。
- `强制结束`：对已勾选进程发送 `SIGKILL`，执行前二次确认。
- `选择子进程`：把当前已勾选父进程的子进程加入选择。
- 提示文案：`只会停止已勾选的进程`。

## 进程数据模型

每个进程归一化为 `ProcessInfo`：

- `pid`
- `ppid`
- `pgid`
- `user`
- `executableName`
- `commandLine`
- `workingDirectory`
- `projectPath`
- `projectName`
- `listeningPorts`
- `source`
- `kind`
- `safety`
- `startedAt`
- `children`

`source` 可取：

- `claudeCode`
- `codex`
- `vsCode`
- `terminal`
- `unknown`

`kind` 可取：

- `devServer`
- `mcp`
- `worker`
- `database`
- `docker`
- `shell`
- `script`
- `app`
- `other`

`safety` 可取：

- `safe`
- `warn`
- `protected`

## 来源识别

来源识别基于父进程链，从当前进程向上追溯到根进程。命中多个来源时使用固定优先级：

`Claude Code > Codex > VS Code > Terminal > Unknown`

识别规则：

- Claude Code：进程名或命令行包含 `claude`，或父进程链中出现 Claude Code CLI。
- Codex：父进程链包含 `/Applications/Codex.app/`、`codex app-server`、`Codex Computer Use`、`node_repl`，或 Codex 相关 helper。
- VS Code：父进程链包含 `/Applications/Visual Studio Code.app/`、`Code Helper`、`ptyHost`、VS Code integrated terminal 相关进程。
- Terminal：父进程链包含 `/System/Applications/Utilities/Terminal.app/`，或 shell 进程可追溯到 Terminal。
- Unknown：父进程已经断开、来源无法归因，或命令来自 launchd 但仍符合开发进程规则。

## 项目识别

项目识别优先级：

1. 使用进程当前工作目录。
2. 从命令行参数中提取路径，例如 `/Users/Zhuanz/sync/code/vibe-projects/my-blog/node_modules/.bin/next`。
3. 向上查找项目标记文件：`package.json`、`.git`、`pyproject.toml`、`Cargo.toml`、`go.mod`、`pnpm-workspace.yaml`。
4. 若找不到项目标记，则使用工作目录最后一级作为项目名。
5. 若工作目录不可访问且命令行没有路径，则归为 `未识别项目`。

## 开发进程过滤

默认显示当前用户的开发相关进程，包含：

- 常见运行时：`node`、`python`、`bun`、`deno`、`ruby`、`java`、`go`。
- 常见 dev server：`vite`、`next`、`astro`、`webpack`、`tsx`、`uvicorn`、`fastapi`、`rails`。
- 常见基础设施：`postgres`、`redis-server`、`docker-proxy`。
- AI 工具相关后台：`mcp-server-*`、`playwright-mcp`、`node_repl`、`Codex Computer Use`。
- shell 派生的长时间命令：`zsh`、`bash`、`sh`，如果其子进程或命令行符合开发进程规则。

默认隐藏：

- macOS 系统进程。
- 非当前用户进程。
- App UI 主进程，除非它是来源分组的根节点且被标记为 `protected`。
- 短命且无项目归属的普通 shell 命令。

## 安全规则

`protected`：

- macOS 系统进程。
- 非当前用户进程。
- `Codex.app`、`Visual Studio Code.app`、Terminal App 主进程。
- 来源工具主控进程，例如 Claude Code 主 CLI，第一版默认保护。

`warn`：

- `postgres`
- `redis-server`
- `docker-proxy`
- 运行时间超过 8 小时的服务进程。
- 没有明确项目归属但符合开发进程规则的后台进程。

`safe`：

- `vite`、`next dev`、`astro`、`webpack` 等 dev server。
- `uvicorn`、`fastapi` 等本地后端服务。
- `mcp-server-*`、`playwright-mcp`、`node_repl`。
- 明确位于项目目录下的 worker 或脚本。

## 生命周期操作

用户必须手动勾选要操作的进程。

- 勾选父进程不会自动勾选子进程。
- `选择子进程` 会把已勾选进程的当前子树加入选择。
- `停止所选` 对已选进程发送 `SIGTERM`，保护进程会被跳过并显示结果。
- `强制结束` 对已选进程发送 `SIGKILL`，执行前展示受影响 PID 列表并要求确认。
- 操作完成后立即刷新进程列表。

## 设置

第一版提供简单设置面板：

- 刷新间隔：`关闭自动刷新`、`3 秒`、`5 秒`、`10 秒`。
- 默认视图：`来源` 或 `项目`。
- 是否显示 protected 进程。
- 项目根目录列表，默认包含 `/Users/Zhuanz/sync/code`、`/Users/Zhuanz/code`、`/Users/Zhuanz/Developer`。

## 测试策略

- 对进程归类规则写 Swift 单元测试，使用固定 fixture 模拟 PID、PPID、命令行和 cwd。
- 对项目识别写单元测试，覆盖 package.json、.git、pyproject.toml、命令行路径推断。
- 对安全规则写单元测试，覆盖 safe、warn、protected。
- 手动验证菜单栏 popover：展开、刷新、搜索、分组切换、勾选、选择子进程、停止所选。

## 第一版验收标准

- App 能作为 macOS 菜单栏应用启动，无 Dock 图标。
- 点击菜单栏图标能展开中文 popover。
- 能显示当前用户的开发进程，包括无端口的 MCP、worker、脚本。
- 能标注来源：Claude Code、Codex、VS Code、Terminal、Unknown。
- 能按来源和项目两种方式查看。
- 能手动勾选进程，并只对已勾选进程执行停止或强制结束。
- 能保护来源工具主进程和系统进程，避免默认误杀。
