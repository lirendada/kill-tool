import Darwin
import Foundation

public enum ProcessCommandError: Error, Equatable, CustomStringConvertible {
    case timedOut

    public var description: String {
        switch self {
        case .timedOut:
            return "command timed out"
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

        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputHandle
        process.standardError = FileHandle.nullDevice

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

        let data = try Data(contentsOf: outputURL)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
