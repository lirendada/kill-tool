import Darwin
import Foundation

public enum ProcessSignal: Equatable, Sendable {
    case terminate
    case kill

    var rawValue: Int32 {
        switch self {
        case .terminate: SIGTERM
        case .kill: SIGKILL
        }
    }
}

public struct ProcessActionResult: Equatable, Identifiable, Sendable {
    public let pid: Int32
    public let signal: ProcessSignal
    public let succeeded: Bool
    public let errorMessage: String?

    public var id: Int32 { pid }

    public init(pid: Int32, signal: ProcessSignal, succeeded: Bool, errorMessage: String?) {
        self.pid = pid
        self.signal = signal
        self.succeeded = succeeded
        self.errorMessage = errorMessage
    }
}

public protocol ProcessIdentityVerifying: Sendable {
    func matches(_ process: RawProcess) -> Bool
}

public struct LiveProcessIdentityVerifier: ProcessIdentityVerifying {
    private let timeoutSeconds: TimeInterval

    public init(timeoutSeconds: TimeInterval = 1) {
        self.timeoutSeconds = timeoutSeconds
    }

    public func matches(_ process: RawProcess) -> Bool {
        do {
            let output = try ProcessCommandRunner.run(
                executable: "/bin/ps",
                arguments: ["-p", String(process.pid), "-o", "user=,command="],
                timeoutSeconds: timeoutSeconds
            )
            guard let liveProcess = Self.parseIdentity(output) else {
                return false
            }

            return liveProcess.user == process.user
                && liveProcess.commandLine == process.commandLine
        } catch {
            return false
        }
    }

    private static func parseIdentity(_ output: String) -> (user: String, commandLine: String)? {
        guard let row = output
            .split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else {
            return nil
        }

        let parts = row.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            return nil
        }

        return (String(parts[0]), String(parts[1]))
    }
}

public protocol ProcessSignalSending: Sendable {
    func send(_ signal: ProcessSignal, to pid: Int32) -> ProcessActionResult
}

public struct DarwinProcessSignalSender: ProcessSignalSending {
    public init() {}

    public func send(_ signal: ProcessSignal, to pid: Int32) -> ProcessActionResult {
        let status = Darwin.kill(pid, signal.rawValue)
        if status == 0 {
            return ProcessActionResult(pid: pid, signal: signal, succeeded: true, errorMessage: nil)
        }

        return ProcessActionResult(
            pid: pid,
            signal: signal,
            succeeded: false,
            errorMessage: String(cString: strerror(errno))
        )
    }
}

public final class ProcessController {
    private let identityVerifier: any ProcessIdentityVerifying
    private let signalSender: any ProcessSignalSending

    public init(
        identityVerifier: any ProcessIdentityVerifying = LiveProcessIdentityVerifier(),
        signalSender: any ProcessSignalSending = DarwinProcessSignalSender()
    ) {
        self.identityVerifier = identityVerifier
        self.signalSender = signalSender
    }

    public func stop(process: DevProcess) -> ProcessActionResult {
        send(.terminate, to: process)
    }

    public func forceKill(process: DevProcess) -> ProcessActionResult {
        send(.kill, to: process)
    }

    private func send(_ signal: ProcessSignal, to process: DevProcess) -> ProcessActionResult {
        guard identityVerifier.matches(process.raw) else {
            return ProcessActionResult(
                pid: process.pid,
                signal: signal,
                succeeded: false,
                errorMessage: "进程身份已变化，请刷新后重试"
            )
        }

        return signalSender.send(signal, to: process.pid)
    }
}
