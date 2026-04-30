import Darwin
import Foundation

public enum ProcessSignal: Equatable {
    case terminate
    case kill

    var rawValue: Int32 {
        switch self {
        case .terminate: SIGTERM
        case .kill: SIGKILL
        }
    }
}

public struct ProcessActionResult: Equatable, Identifiable {
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

public final class ProcessController {
    public init() {}

    public func stop(pid: Int32) -> ProcessActionResult {
        send(.terminate, to: pid)
    }

    public func forceKill(pid: Int32) -> ProcessActionResult {
        send(.kill, to: pid)
    }

    private func send(_ signal: ProcessSignal, to pid: Int32) -> ProcessActionResult {
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
