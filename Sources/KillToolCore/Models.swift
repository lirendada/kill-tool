import Foundation

public enum ProcessSource: String, CaseIterable, Equatable, Hashable, Identifiable {
    case claudeCode
    case codex
    case vsCode
    case terminal
    case unknown

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .vsCode: "VS Code"
        case .terminal: "Terminal"
        case .unknown: "Unknown"
        }
    }

    public var priority: Int {
        switch self {
        case .claudeCode: 0
        case .codex: 1
        case .vsCode: 2
        case .terminal: 3
        case .unknown: 4
        }
    }
}

public enum ProcessKind: String, Equatable, Hashable, Identifiable {
    case devServer
    case mcp
    case worker
    case database
    case docker
    case shell
    case script
    case app
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .devServer: "开发服务"
        case .mcp: "MCP"
        case .worker: "工作进程"
        case .database: "数据库"
        case .docker: "Docker"
        case .shell: "Shell"
        case .script: "脚本"
        case .app: "应用"
        case .other: "其他"
        }
    }
}

public enum SafetyLevel: String, Equatable, Hashable, Identifiable {
    case safe
    case warn
    case protected

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .safe: "安全"
        case .warn: "谨慎"
        case .protected: "保护"
        }
    }
}

public struct RawProcess: Equatable, Identifiable, Hashable {
    public let pid: Int32
    public let ppid: Int32
    public let pgid: Int32
    public let user: String
    public let executableName: String
    public let commandLine: String
    public let workingDirectory: String?
    public let startedAt: Date

    public var id: Int32 { pid }

    public init(
        pid: Int32,
        ppid: Int32,
        pgid: Int32,
        user: String,
        executableName: String,
        commandLine: String,
        workingDirectory: String?,
        startedAt: Date
    ) {
        self.pid = pid
        self.ppid = ppid
        self.pgid = pgid
        self.user = user
        self.executableName = executableName
        self.commandLine = commandLine
        self.workingDirectory = workingDirectory
        self.startedAt = startedAt
    }
}

public struct DevProcess: Equatable, Identifiable, Hashable {
    public let raw: RawProcess
    public let projectPath: String?
    public let projectName: String
    public let listeningPorts: [Int]
    public let source: ProcessSource
    public let kind: ProcessKind
    public let safety: SafetyLevel
    public var children: [DevProcess]

    public var id: Int32 { raw.pid }
    public var pid: Int32 { raw.pid }
    public var ppid: Int32 { raw.ppid }
    public var commandLine: String { raw.commandLine }
    public var executableName: String { raw.executableName }

    public init(
        raw: RawProcess,
        projectPath: String?,
        projectName: String,
        listeningPorts: [Int],
        source: ProcessSource,
        kind: ProcessKind,
        safety: SafetyLevel,
        children: [DevProcess] = []
    ) {
        self.raw = raw
        self.projectPath = projectPath
        self.projectName = projectName
        self.listeningPorts = listeningPorts
        self.source = source
        self.kind = kind
        self.safety = safety
        self.children = children
    }
}
