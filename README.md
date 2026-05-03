# KillTool

macOS 菜单栏应用，用于监控和管理开发进程。自动识别 Claude Code、Codex、VS Code、Terminal 等来源启动的开发服务、MCP 服务、工作进程等，支持一键停止或强制结束。

## 功能

- **自动扫描** — 每分钟刷新当前用户的开发进程，显示 PID、CPU、内存、监听端口等信息
- **来源识别** — 自动追溯父进程链，识别进程来源（Claude Code / Codex / VS Code / Terminal）
- **分类展示** — 按类型（开发服务、MCP、数据库、Docker 等）分类，支持按来源或项目分组查看
- **安全分级** — 进程标记为安全 / 谨慎 / 保护三个等级，防止误杀关键进程
- **进程树** — 以树形结构展示父子进程关系，可一键选中子进程
- **搜索过滤** — 支持按进程名、端口、项目名搜索
- **停止 / 强制结束** — SIGTERM 优雅停止，SIGKILL 强制结束

## 依赖

- macOS 13.0+
- Xcode 15.0+ / Swift 5.9+
- 无第三方依赖

## 构建

```bash
swift build -c release
```

产物位于 `.build/release/KillTool`。

## 运行

```bash
swift run
```

点击菜单栏闪电图标打开面板，右键点击可退出应用。

## 项目结构

```
Sources/
├── KillToolCore/          # 核心逻辑（无 UI 依赖）
│   ├── Models.swift       # 数据模型
│   ├── ProcessScanner.swift
│   ├── ProcessClassifier.swift
│   ├── ProcessController.swift
│   ├── ProcessCommandRunner.swift
│   ├── ProjectResolver.swift
│   ├── ProcessDisplayFormatter.swift
│   └── ProcessScanResult.swift
└── KillToolApp/           # macOS 菜单栏应用
    ├── KillToolMain.swift
    ├── ProcessStore.swift
    └── Views/
        ├── ProcessDashboardView.swift
        └── ProcessRowView.swift
Tests/
└── KillToolCoreBehaviorTests/
```

## License

MIT
