import Foundation

public enum ProcessClassifier {
    public static func source(for process: RawProcess, in index: [Int32: RawProcess]) -> ProcessSource {
        let chain = ancestorChain(startingAt: process, in: index)
        let matched = chain.map(sourceMarker(for:)).filter { $0 != .unknown }
        return matched.min { $0.priority < $1.priority } ?? .unknown
    }

    public static func kind(for process: RawProcess) -> ProcessKind {
        kind(forCommandLine: process.commandLine, executableName: process.executableName)
    }

    public static func kind(forCommandLine commandLine: String) -> ProcessKind {
        kind(forCommandLine: commandLine, executableName: "")
    }

    public static func safety(
        for process: RawProcess,
        kind: ProcessKind,
        currentUser: String,
        now: Date = Date()
    ) -> SafetyLevel {
        guard process.user == currentUser else {
            return .protected
        }

        let lowerCommand = process.commandLine.lowercased()
        let lowerName = process.executableName.lowercased()

        if kind == .app {
            return .protected
        }

        if lowerCommand.contains("/applications/codex.app/")
            || lowerCommand.contains("/applications/visual studio code.app/")
            || lowerCommand.contains("/system/applications/utilities/terminal.app/")
            || lowerName == "claude" {
            return .protected
        }

        if kind == .database || kind == .docker {
            return .warn
        }

        if now.timeIntervalSince(process.startedAt) > 8 * 60 * 60 {
            return .warn
        }

        switch kind {
        case .devServer, .mcp, .worker, .script:
            return .safe
        case .shell, .other:
            return process.workingDirectory == nil ? .warn : .safe
        case .database, .docker:
            return .warn
        case .app:
            return .protected
        }
    }

    private static func ancestorChain(startingAt process: RawProcess, in index: [Int32: RawProcess]) -> [RawProcess] {
        var chain: [RawProcess] = []
        var current: RawProcess? = process
        var seen: Set<Int32> = []

        while let node = current, !seen.contains(node.pid) {
            chain.append(node)
            seen.insert(node.pid)
            current = index[node.ppid]
        }

        return chain
    }

    private static func sourceMarker(for process: RawProcess) -> ProcessSource {
        let haystack = "\(process.executableName) \(process.commandLine)".lowercased()

        if process.executableName.lowercased() == "claude"
            || haystack.contains(" claude ")
            || haystack.hasPrefix("claude ")
            || haystack.contains("/claude") {
            return .claudeCode
        }

        if haystack.contains("/applications/codex.app/")
            || haystack.contains("codex app-server")
            || haystack.contains("codex computer use")
            || haystack.contains("node_repl") {
            return .codex
        }

        if haystack.contains("/applications/visual studio code.app/")
            || haystack.contains("code helper")
            || haystack.contains("ptyhost") {
            return .vsCode
        }

        if haystack.contains("/system/applications/utilities/terminal.app/")
            || process.executableName.lowercased() == "terminal" {
            return .terminal
        }

        return .unknown
    }

    private static func kind(forCommandLine commandLine: String, executableName: String) -> ProcessKind {
        let lower = "\(executableName) \(commandLine)".lowercased()

        if lower.contains(".app/contents/macos/") {
            return .app
        }

        if lower.contains("mcp-server")
            || lower.contains("playwright-mcp")
            || lower.contains("node_repl")
            || lower.hasSuffix(" mcp")
            || lower.contains(" mcp ") {
            return .mcp
        }

        if lower.contains("docker-proxy") {
            return .docker
        }

        if lower.contains("postgres")
            || lower.contains("redis-server")
            || lower.contains("mysqld")
            || lower.contains("mongod") {
            return .database
        }

        if lower.contains("next dev")
            || lower.contains("/next dev")
            || lower.contains("next-server")
            || lower.contains("vite")
            || lower.contains("astro dev")
            || lower.contains("webpack")
            || lower.contains("uvicorn")
            || lower.contains("fastapi")
            || lower.contains("rails server")
            || lower.contains("npm run dev")
            || lower.contains("pnpm dev")
            || lower.contains("yarn dev")
            || lower.contains("bun dev") {
            return .devServer
        }

        if lower.contains("worker") {
            return .worker
        }

        if lower.hasPrefix("zsh ")
            || lower.hasPrefix("bash ")
            || lower.hasPrefix("sh ")
            || lower.contains("/bin/zsh")
            || lower.contains("/bin/bash")
            || lower.contains("/bin/sh") {
            return .shell
        }

        if lower.hasPrefix("node ")
            || lower.hasPrefix("python ")
            || lower.hasPrefix("python3 ")
            || lower.hasPrefix("bun ")
            || lower.hasPrefix("deno ")
            || lower.hasPrefix("ruby ")
            || lower.hasPrefix("java ")
            || lower.hasPrefix("go ") {
            return .script
        }

        return .other
    }
}
