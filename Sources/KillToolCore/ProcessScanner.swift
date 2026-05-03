import Foundation

public final class ProcessScanner {
    public let currentUser: String
    private let commandTimeoutSeconds: TimeInterval

    public init(currentUser: String = NSUserName(), commandTimeoutSeconds: TimeInterval = 2.5) {
        self.currentUser = currentUser
        self.commandTimeoutSeconds = commandTimeoutSeconds
    }

    public func scan() -> [DevProcess] {
        scanDetailed().processes
    }

    public func scanDetailed() -> ProcessScanResult {
        let now = Date()
        var errors: [String] = []
        let psOutput = capture(
            label: "ps",
            executable: "/bin/ps",
            arguments: ["-axo", "pid=,ppid=,pgid=,user=,etime=,command="],
            errors: &errors
        )
        let cwdOutput = capture(
            label: "cwd lsof",
            executable: "/usr/sbin/lsof",
            arguments: ["-nP", "-Fpcn", "-a", "-d", "cwd", "-u", currentUser],
            errors: &errors
        )
        let portOutput = capture(
            label: "port lsof",
            executable: "/usr/sbin/lsof",
            arguments: Self.listeningPortLsofArguments(currentUser: currentUser),
            errors: &errors
        )

        let cwdByPID = Self.parseWorkingDirectories(cwdOutput)
        let portsByPID = Self.parseListeningPorts(portOutput)
        let rawProcesses = psOutput
            .split(whereSeparator: \.isNewline)
            .compactMap { Self.parsePSRow(String($0), now: now) }

        return ProcessScanResult(
            processes: Self.classify(
                rawProcesses: rawProcesses,
                cwdByPID: cwdByPID,
                portsByPID: portsByPID,
                currentUser: currentUser,
                now: now
            ),
            errors: errors
        )
    }

    public static func classify(
        rawProcesses: [RawProcess],
        cwdByPID: [Int32: String],
        portsByPID: [Int32: [Int]],
        currentUser: String,
        now: Date
    ) -> [DevProcess] {
        let rawProcesses = rawProcesses.map { raw in
            RawProcess(
                pid: raw.pid,
                ppid: raw.ppid,
                pgid: raw.pgid,
                user: raw.user,
                executableName: raw.executableName,
                commandLine: raw.commandLine,
                workingDirectory: cwdByPID[raw.pid] ?? raw.workingDirectory,
                startedAt: raw.startedAt
            )
        }
        let rawIndex = Dictionary(uniqueKeysWithValues: rawProcesses.map { ($0.pid, $0) })

        return rawProcesses
            .filter { $0.user == currentUser }
            .map { raw -> (RawProcess, ProcessSource, ProcessKind, SafetyLevel) in
                let source = ProcessClassifier.source(for: raw, in: rawIndex)
                let kind = ProcessClassifier.kind(for: raw)
                let safety = ProcessClassifier.safety(for: raw, kind: kind, currentUser: currentUser, now: now)
                return (raw, source, kind, safety)
            }
            .filter { raw, source, kind, _ in
                Self.isDevelopmentCandidate(raw: raw, source: source, kind: kind, ports: portsByPID[raw.pid] ?? [])
            }
            .map { raw, source, kind, safety in
                let project = ProjectResolver.resolve(
                    workingDirectory: raw.workingDirectory,
                    commandLine: raw.commandLine
                )

                return DevProcess(
                    raw: raw,
                    projectPath: project.path.isEmpty ? nil : project.path,
                    projectName: project.name,
                    listeningPorts: portsByPID[raw.pid] ?? [],
                    source: source,
                    kind: kind,
                    safety: safety
                )
            }
            .sorted { lhs, rhs in
                if lhs.source.priority != rhs.source.priority {
                    return lhs.source.priority < rhs.source.priority
                }
                if lhs.projectName != rhs.projectName {
                    return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
                }
                return lhs.pid < rhs.pid
            }
    }

    public static func parsePSRow(_ row: String, now: Date = Date()) -> RawProcess? {
        let parts = row.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
        guard parts.count == 6,
              let pid = Int32(parts[0]),
              let ppid = Int32(parts[1]),
              let pgid = Int32(parts[2]) else {
            return nil
        }

        let user = String(parts[3])
        let elapsed = String(parts[4])
        let commandLine = String(parts[5])
        let executableName = deriveExecutableName(from: commandLine)
        let startedAt = now.addingTimeInterval(-TimeInterval(parseElapsedSeconds(elapsed)))

        return RawProcess(
            pid: pid,
            ppid: ppid,
            pgid: pgid,
            user: user,
            executableName: executableName,
            commandLine: commandLine,
            workingDirectory: nil,
            startedAt: startedAt
        )
    }

    public static func listeningPortLsofArguments(currentUser: String) -> [String] {
        ["-nP", "-a", "-iTCP", "-sTCP:LISTEN", "-Fpcn", "-u", currentUser]
    }

    public static func parseListeningPorts(_ output: String) -> [Int32: [Int]] {
        var currentPID: Int32?
        var portsByPID: [Int32: Set<Int>] = [:]

        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            if line.hasPrefix("p"), let pid = Int32(line.dropFirst()) {
                currentPID = pid
                continue
            }

            guard line.hasPrefix("n"), let pid = currentPID else {
                continue
            }

            if let port = parsePort(from: String(line.dropFirst())) {
                portsByPID[pid, default: []].insert(port)
            }
        }

        return portsByPID.mapValues { $0.sorted() }
    }

    public static func parseWorkingDirectories(_ output: String) -> [Int32: String] {
        var currentPID: Int32?
        var directories: [Int32: String] = [:]

        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            if line.hasPrefix("p"), let pid = Int32(line.dropFirst()) {
                currentPID = pid
                continue
            }

            guard line.hasPrefix("n"), let pid = currentPID else {
                continue
            }

            directories[pid] = String(line.dropFirst())
        }

        return directories
    }

    private static func isDevelopmentCandidate(
        raw: RawProcess,
        source: ProcessSource,
        kind: ProcessKind,
        ports: [Int]
    ) -> Bool {
        if !ports.isEmpty {
            return true
        }

        switch kind {
        case .devServer, .mcp, .worker, .database, .docker, .script:
            return true
        case .shell, .app, .other:
            return false
        }
    }

    private static func deriveExecutableName(from commandLine: String) -> String {
        guard let first = commandLine.split(separator: " ").first else {
            return ""
        }

        let token = String(first).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if token.hasPrefix("/") {
            return URL(fileURLWithPath: token).lastPathComponent
        }
        return token
    }

    private static func parseElapsedSeconds(_ elapsed: String) -> Int {
        var remaining = elapsed
        var days = 0

        if let dash = remaining.firstIndex(of: "-") {
            days = Int(remaining[..<dash]) ?? 0
            remaining = String(remaining[remaining.index(after: dash)...])
        }

        let values = remaining
            .split(separator: ":")
            .compactMap { Int($0) }

        let seconds: Int
        switch values.count {
        case 3:
            seconds = values[0] * 3600 + values[1] * 60 + values[2]
        case 2:
            seconds = values[0] * 60 + values[1]
        case 1:
            seconds = values[0]
        default:
            seconds = 0
        }

        return days * 24 * 3600 + seconds
    }

    private static func parsePort(from endpoint: String) -> Int? {
        guard let colon = endpoint.lastIndex(of: ":") else {
            return nil
        }

        let portPart = endpoint[endpoint.index(after: colon)...]
        return Int(portPart)
    }

    private func capture(
        label: String,
        executable: String,
        arguments: [String],
        errors: inout [String]
    ) -> String {
        do {
            return try ProcessCommandRunner.run(
                executable: executable,
                arguments: arguments,
                timeoutSeconds: commandTimeoutSeconds
            )
        } catch {
            errors.append("\(label): \(error)")
            return ""
        }
    }
}
