public struct ProcessScanResult: Equatable, Sendable {
    public let processes: [DevProcess]
    public let errors: [String]

    public init(processes: [DevProcess], errors: [String]) {
        self.processes = processes
        self.errors = errors
    }
}
