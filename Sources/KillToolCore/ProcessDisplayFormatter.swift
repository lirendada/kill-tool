import Foundation

public enum ProcessDisplayFormatter {
    public static func primaryTitle(for process: DevProcess) -> String {
        "\(process.projectName) · \(process.kind.displayName)"
    }

    public static func commandAction(for process: DevProcess) -> String {
        let commandLine = process.commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerCommand = commandLine.lowercased()

        for pattern in orderedCommandPatterns where lowerCommand.contains(pattern.match) {
            return pattern.display
        }

        for token in commandLine.split(separator: " ").map(String.init) {
            let name = lastPathComponent(from: token).lowercased()
            if name == "vite"
                || name == "webpack"
                || name == "playwright-mcp"
                || name == "node_repl"
                || name == "postgres"
                || name == "redis-server"
                || name == "docker-proxy"
                || name.hasPrefix("mcp-server-") {
                return name
            }
        }

        if !process.executableName.isEmpty {
            return process.executableName
        }

        return commandLine
            .split(separator: " ")
            .first
            .map(String.init) ?? "未知命令"
    }

    public static func resourceSummary(for process: DevProcess) -> String {
        "\(cpuBadgeText(for: process)) · \(memoryBadgeText(for: process))"
    }

    public static func cpuBadgeText(for process: DevProcess) -> String {
        "CPU \(percentText(process.cpuPercent))"
    }

    public static func memoryBadgeText(for process: DevProcess) -> String {
        "内存 \(percentText(process.memoryPercent))"
    }

    private static let orderedCommandPatterns: [(match: String, display: String)] = [
        ("npm run dev", "npm run dev"),
        ("pnpm dev", "pnpm dev"),
        ("yarn dev", "yarn dev"),
        ("bun dev", "bun dev"),
        ("next dev", "next dev"),
        ("astro dev", "astro dev"),
        ("rails server", "rails server")
    ]

    private static func lastPathComponent(from token: String) -> String {
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard trimmed.contains("/") else {
            return trimmed
        }
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    private static func percentText(_ value: Double) -> String {
        if abs(value) < 0.05 {
            return "0%"
        }
        return String(format: "%.1f%%", value)
    }
}
