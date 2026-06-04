import Foundation

public enum ProcessSource: String, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
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

public enum ProcessKind: String, Equatable, Hashable, Identifiable, Sendable {
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

public enum SafetyLevel: String, Equatable, Hashable, Identifiable, Sendable {
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

public struct ListeningPort: Equatable, Hashable, Sendable {
    public let port: Int
    public let endpoint: String

    public init(port: Int, endpoint: String) {
        self.port = port
        self.endpoint = endpoint
    }

    public var isWildcard: Bool {
        let normalized = endpoint.lowercased()
        return normalized.hasPrefix("*:")
            || normalized.hasPrefix("0.0.0.0:")
            || normalized.hasPrefix("[::]:")
    }

    public var isLocalOnly: Bool {
        let normalized = endpoint.lowercased()
        return normalized.hasPrefix("127.")
            || normalized.hasPrefix("localhost:")
            || normalized.hasPrefix("[::1]:")
            || normalized.hasPrefix("::1:")
    }
}

public enum PortCategory: String, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
    case protected
    case exposed
    case devService
    case database
    case local
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .protected: "低位保护"
        case .exposed: "对外暴露"
        case .devService: "开发服务"
        case .database: "数据库"
        case .local: "本地监听"
        case .other: "其他端口"
        }
    }

    public var priority: Int {
        switch self {
        case .protected: 0
        case .exposed: 1
        case .devService: 2
        case .database: 3
        case .local: 4
        case .other: 5
        }
    }

    public static func classify(port: ListeningPort, processKind: ProcessKind) -> PortCategory {
        if port.port < 1024 {
            return .protected
        }
        if port.isWildcard {
            return .exposed
        }
        if processKind == .database || knownDatabasePorts.contains(port.port) {
            return .database
        }
        if processKind == .devServer || knownDevelopmentPorts.contains(port.port) {
            return .devService
        }
        if port.isLocalOnly {
            return .local
        }
        return .other
    }

    private static let knownDevelopmentPorts: Set<Int> = [
        3000, 3001, 4173, 5000, 5173, 8000, 8080
    ]

    private static let knownDatabasePorts: Set<Int> = [
        3306, 5432, 6379, 9200, 27017
    ]
}

public struct RawProcess: Equatable, Identifiable, Hashable, Sendable {
    public let pid: Int32
    public let ppid: Int32
    public let pgid: Int32
    public let user: String
    public let executableName: String
    public let commandLine: String
    public let workingDirectory: String?
    public let startedAt: Date
    public let cpuPercent: Double
    public let memoryPercent: Double
    public let cpuTimeSeconds: Double

    public var id: Int32 { pid }

    public init(
        pid: Int32,
        ppid: Int32,
        pgid: Int32,
        user: String,
        executableName: String,
        commandLine: String,
        workingDirectory: String?,
        startedAt: Date,
        cpuPercent: Double = 0,
        memoryPercent: Double = 0,
        cpuTimeSeconds: Double = 0
    ) {
        self.pid = pid
        self.ppid = ppid
        self.pgid = pgid
        self.user = user
        self.executableName = executableName
        self.commandLine = commandLine
        self.workingDirectory = workingDirectory
        self.startedAt = startedAt
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.cpuTimeSeconds = cpuTimeSeconds
    }
}

public struct DevProcess: Equatable, Identifiable, Hashable, Sendable {
    public let raw: RawProcess
    public let projectPath: String?
    public let projectName: String
    public let listeningPorts: [Int]
    public let listeningPortDetails: [ListeningPort]
    public let source: ProcessSource
    public let kind: ProcessKind
    public let safety: SafetyLevel
    public var children: [DevProcess]
    public var instantaneousCPUPercent: Double?

    public var id: Int32 { raw.pid }
    public var pid: Int32 { raw.pid }
    public var ppid: Int32 { raw.ppid }
    public var commandLine: String { raw.commandLine }
    public var executableName: String { raw.executableName }
    public var cpuPercent: Double { raw.cpuPercent }
    public var memoryPercent: Double { raw.memoryPercent }

    public init(
        raw: RawProcess,
        projectPath: String?,
        projectName: String,
        listeningPorts: [Int],
        listeningPortDetails: [ListeningPort] = [],
        source: ProcessSource,
        kind: ProcessKind,
        safety: SafetyLevel,
        children: [DevProcess] = [],
        instantaneousCPUPercent: Double? = nil
    ) {
        self.raw = raw
        self.projectPath = projectPath
        self.projectName = projectName
        self.listeningPorts = listeningPorts
        self.listeningPortDetails = listeningPortDetails.isEmpty
            ? listeningPorts.map { ListeningPort(port: $0, endpoint: ":\($0)") }
            : listeningPortDetails
        self.source = source
        self.kind = kind
        self.safety = safety
        self.children = children
        self.instantaneousCPUPercent = instantaneousCPUPercent
    }
}
