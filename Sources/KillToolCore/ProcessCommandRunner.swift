import Darwin
import Foundation

public enum ProcessCommandError: Error, Equatable, CustomStringConvertible, Sendable {
    case timedOut
    case failed(exitCode: Int32, errorSummary: String)

    public var description: String {
        switch self {
        case .timedOut:
            return "command timed out"
        case .failed(let exitCode, let errorSummary):
            guard !errorSummary.isEmpty else {
                return "command exited with status \(exitCode)"
            }
            return "command exited with status \(exitCode): \(errorSummary)"
        }
    }
}

public enum ProcessCommandRunner {
    public static func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) throws -> String {
        let process = Process()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("killtool-\(UUID().uuidString).out")
        let errorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("killtool-\(UUID().uuidString).err")

        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        try process.run()

        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            finished.signal()
        }

        if finished.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 0.5) == .timedOut {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.5)
            }
            throw ProcessCommandError.timedOut
        }

        try outputHandle.close()
        try errorHandle.close()

        let data = try Data(contentsOf: outputURL)
        if process.terminationStatus != 0 {
            let errorData = try Data(contentsOf: errorURL)
            throw ProcessCommandError.failed(
                exitCode: process.terminationStatus,
                errorSummary: errorSummary(from: errorData)
            )
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func errorSummary(from data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? ""
        let summary = text
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return String(summary.prefix(400))
    }
}
