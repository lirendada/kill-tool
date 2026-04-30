import Foundation

public struct ProjectIdentity: Equatable, Hashable {
    public let path: String
    public let name: String

    public init(path: String, name: String) {
        self.path = path
        self.name = name
    }
}

public enum ProjectResolver {
    private static let markerFiles = [
        "package.json",
        ".git",
        "pyproject.toml",
        "Cargo.toml",
        "go.mod",
        "pnpm-workspace.yaml"
    ]

    public static func resolve(workingDirectory: String?, commandLine: String) -> ProjectIdentity {
        if let workingDirectory,
           let projectRoot = nearestProjectRoot(from: URL(fileURLWithPath: workingDirectory, isDirectory: true)) {
            return identity(for: projectRoot)
        }

        for path in absolutePaths(in: commandLine) {
            let url = URL(fileURLWithPath: path)
            let start = FileManager.default.fileExists(atPath: url.path) ? url : url.deletingLastPathComponent()
            if let projectRoot = nearestProjectRoot(from: start) {
                return identity(for: projectRoot)
            }
        }

        if let workingDirectory {
            let url = URL(fileURLWithPath: workingDirectory, isDirectory: true)
            return ProjectIdentity(path: url.path, name: url.lastPathComponent)
        }

        return ProjectIdentity(path: "", name: "未识别项目")
    }

    private static func nearestProjectRoot(from start: URL) -> URL? {
        var current = start.standardizedFileURL

        while true {
            if markerFiles.contains(where: { FileManager.default.fileExists(atPath: current.appendingPathComponent($0).path) }) {
                return current
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }

        return nil
    }

    private static func identity(for url: URL) -> ProjectIdentity {
        let standardized = url.standardizedFileURL
        return ProjectIdentity(path: standardized.path, name: standardized.lastPathComponent)
    }

    private static func absolutePaths(in commandLine: String) -> [String] {
        commandLine
            .split(separator: " ")
            .map(String.init)
            .filter { $0.hasPrefix("/") }
            .map { token in
                token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
    }
}
