import Foundation
import KillToolCore

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("FAIL: \(message)\nExpected: \(expected)\nActual: \(actual)\n", stderr)
        Foundation.exit(1)
    }
}

func testClaudeCodeTakesPriorityOverTerminalAncestor() {
    let terminal = RawProcess(
        pid: 100,
        ppid: 1,
        pgid: 100,
        user: "Zhuanz",
        executableName: "Terminal",
        commandLine: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal",
        workingDirectory: nil,
        startedAt: Date()
    )
    let claude = RawProcess(
        pid: 200,
        ppid: 100,
        pgid: 200,
        user: "Zhuanz",
        executableName: "claude",
        commandLine: "claude --dangerously-skip-permissions",
        workingDirectory: "/Users/Zhuanz/sync/code/vibe-projects/kill-tool",
        startedAt: Date()
    )
    let vite = RawProcess(
        pid: 300,
        ppid: 200,
        pgid: 200,
        user: "Zhuanz",
        executableName: "node",
        commandLine: "node node_modules/.bin/vite --host 0.0.0.0",
        workingDirectory: "/Users/Zhuanz/sync/code/vibe-projects/kill-tool",
        startedAt: Date()
    )

    let index: [Int32: RawProcess] = [100: terminal, 200: claude, 300: vite]

    expectEqual(
        ProcessClassifier.source(for: vite, in: index),
        .claudeCode,
        "Claude Code should outrank Terminal when both are ancestors"
    )
}

func testCodexSourceIsDetectedFromAncestorPath() {
    let codex = RawProcess(
        pid: 10,
        ppid: 1,
        pgid: 10,
        user: "Zhuanz",
        executableName: "codex app-server",
        commandLine: "/Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled",
        workingDirectory: nil,
        startedAt: Date()
    )
    let mcp = RawProcess(
        pid: 11,
        ppid: 10,
        pgid: 10,
        user: "Zhuanz",
        executableName: "node",
        commandLine: "node /Users/Zhuanz/.npm/_npx/15b/node_modules/.bin/mcp-server-memory",
        workingDirectory: "/Users/Zhuanz/sync/code/vibe-projects/kill-tool",
        startedAt: Date()
    )

    expectEqual(
        ProcessClassifier.source(for: mcp, in: [Int32(10): codex, Int32(11): mcp]),
        .codex,
        "Codex descendants should be labeled as Codex"
    )
}

func testVSCodeSourceIsDetectedFromPtyHostAncestor() {
    let ptyHost = RawProcess(
        pid: 20,
        ppid: 1,
        pgid: 20,
        user: "Zhuanz",
        executableName: "Code Helper",
        commandLine: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper --type=ptyHost",
        workingDirectory: nil,
        startedAt: Date()
    )
    let next = RawProcess(
        pid: 21,
        ppid: 20,
        pgid: 20,
        user: "Zhuanz",
        executableName: "node",
        commandLine: "node /Users/Zhuanz/sync/code/vibe-projects/my-blog/node_modules/.bin/next dev",
        workingDirectory: "/Users/Zhuanz/sync/code/vibe-projects/my-blog",
        startedAt: Date()
    )

    expectEqual(
        ProcessClassifier.source(for: next, in: [Int32(20): ptyHost, Int32(21): next]),
        .vsCode,
        "VS Code ptyHost descendants should be labeled as VS Code"
    )
}

func testKindDetectionForMCPDevServerAndDatabase() {
    expectEqual(
        ProcessClassifier.kind(forCommandLine: "node /Users/Zhuanz/.npm/_npx/abc/node_modules/.bin/mcp-server-memory"),
        .mcp,
        "mcp-server commands should be MCP"
    )
    expectEqual(
        ProcessClassifier.kind(forCommandLine: "node node_modules/.bin/next dev --turbopack"),
        .devServer,
        "next dev should be a dev server"
    )
    expectEqual(
        ProcessClassifier.kind(forCommandLine: "next-server (v15.5.15)"),
        .devServer,
        "next-server listener should be a dev server"
    )
    expectEqual(
        ProcessClassifier.kind(forCommandLine: "postgres -D /opt/homebrew/var/postgresql@16"),
        .database,
        "postgres should be a database"
    )
}

func testSafetyLevelsProtectAppsWarnDatabasesAndAllowMCP() {
    let app = RawProcess(
        pid: 1,
        ppid: 0,
        pgid: 1,
        user: "Zhuanz",
        executableName: "Codex",
        commandLine: "/Applications/Codex.app/Contents/MacOS/Codex",
        workingDirectory: nil,
        startedAt: Date()
    )
    let database = RawProcess(
        pid: 2,
        ppid: 1,
        pgid: 2,
        user: "Zhuanz",
        executableName: "postgres",
        commandLine: "postgres -D /opt/homebrew/var/postgresql@16",
        workingDirectory: nil,
        startedAt: Date()
    )
    let mcp = RawProcess(
        pid: 3,
        ppid: 1,
        pgid: 3,
        user: "Zhuanz",
        executableName: "node",
        commandLine: "node /Users/Zhuanz/.npm/_npx/abc/node_modules/.bin/playwright-mcp",
        workingDirectory: "/Users/Zhuanz/sync/code/vibe-projects/kill-tool",
        startedAt: Date()
    )

    expectEqual(
        ProcessClassifier.safety(for: app, kind: .app, currentUser: "Zhuanz"),
        .protected,
        "app main processes should be protected"
    )
    expectEqual(
        ProcessClassifier.safety(for: database, kind: .database, currentUser: "Zhuanz"),
        .warn,
        "databases should require caution"
    )
    expectEqual(
        ProcessClassifier.safety(for: mcp, kind: .mcp, currentUser: "Zhuanz"),
        .safe,
        "MCP server processes should be safe to stop"
    )
}

func testProjectResolverUsesNearestProjectMarkerFromWorkingDirectory() throws {
    let temporaryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("kill-tool-tests-\(UUID().uuidString)", isDirectory: true)
    let projectRoot = temporaryRoot.appendingPathComponent("my-blog", isDirectory: true)
    let nestedDirectory = projectRoot.appendingPathComponent("src/app", isDirectory: true)

    try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
    FileManager.default.createFile(
        atPath: projectRoot.appendingPathComponent("package.json").path,
        contents: Data("{}".utf8)
    )
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    let result = ProjectResolver.resolve(
        workingDirectory: nestedDirectory.path,
        commandLine: "node node_modules/.bin/next dev"
    )

    expectEqual(result.path, projectRoot.path, "working directory marker should resolve project root")
    expectEqual(result.name, "my-blog", "project name should come from resolved root")
}

func testProjectResolverInfersProjectFromCommandLinePath() throws {
    let temporaryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("kill-tool-tests-\(UUID().uuidString)", isDirectory: true)
    let projectRoot = temporaryRoot.appendingPathComponent("api-server", isDirectory: true)
    let binaryDirectory = projectRoot.appendingPathComponent("node_modules/.bin", isDirectory: true)

    try FileManager.default.createDirectory(at: binaryDirectory, withIntermediateDirectories: true)
    FileManager.default.createFile(
        atPath: projectRoot.appendingPathComponent("package.json").path,
        contents: Data("{}".utf8)
    )
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    let commandLine = "node \(binaryDirectory.appendingPathComponent("vite").path) --host 0.0.0.0"
    let result = ProjectResolver.resolve(workingDirectory: nil, commandLine: commandLine)

    expectEqual(result.path, projectRoot.path, "absolute argv path should resolve project root")
    expectEqual(result.name, "api-server", "project name should come from argv-derived root")
}

func testProcessScannerParsesPSRows() {
    let now = Date(timeIntervalSince1970: 1_000)
    let row = "39869 39849 39849 Zhuanz 02:00 node /Users/Zhuanz/sync/code/vibe-projects/my-blog/node_modules/.bin/next dev --turbopack"

    guard let raw = ProcessScanner.parsePSRow(row, now: now) else {
        fputs("FAIL: ps row should parse\n", stderr)
        Foundation.exit(1)
    }

    expectEqual(raw.pid, 39869, "ps parser should read pid")
    expectEqual(raw.ppid, 39849, "ps parser should read ppid")
    expectEqual(raw.pgid, 39849, "ps parser should read pgid")
    expectEqual(raw.user, "Zhuanz", "ps parser should read user")
    expectEqual(raw.executableName, "node", "ps parser should derive executable name")
    expectEqual(raw.commandLine, "node /Users/Zhuanz/sync/code/vibe-projects/my-blog/node_modules/.bin/next dev --turbopack", "ps parser should preserve command line")
    expectEqual(raw.startedAt, Date(timeIntervalSince1970: 880), "ps parser should derive start time from elapsed time")
}

func testProcessScannerParsesListeningPortsFromLsof() {
    let output = """
    p39869
    n*:3000
    p12345
    n127.0.0.1:5173
    n[::1]:4173
    """

    let ports = ProcessScanner.parseListeningPorts(output)

    expectEqual(ports[39869] ?? [], [3000], "lsof parser should read wildcard listener port")
    expectEqual(ports[12345] ?? [], [4173, 5173], "lsof parser should sort multiple listener ports")
}

func testProcessScannerUsesIntersectionForListeningPortLsofQuery() {
    let arguments = ProcessScanner.listeningPortLsofArguments(currentUser: "Zhuanz")

    expectEqual(arguments.contains("-a"), true, "lsof listener query should intersect user and TCP filters")
}

testClaudeCodeTakesPriorityOverTerminalAncestor()
testCodexSourceIsDetectedFromAncestorPath()
testVSCodeSourceIsDetectedFromPtyHostAncestor()
testKindDetectionForMCPDevServerAndDatabase()
testSafetyLevelsProtectAppsWarnDatabasesAndAllowMCP()
try testProjectResolverUsesNearestProjectMarkerFromWorkingDirectory()
try testProjectResolverInfersProjectFromCommandLinePath()
testProcessScannerParsesPSRows()
testProcessScannerParsesListeningPortsFromLsof()
testProcessScannerUsesIntersectionForListeningPortLsofQuery()

print("KillToolCoreBehaviorTests passed")
