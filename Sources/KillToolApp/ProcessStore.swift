import Combine
import Foundation
import KillToolCore

enum ProcessViewMode: String, CaseIterable, Identifiable {
    case source = "来源"
    case project = "项目"
    case port = "端口"

    var id: String { rawValue }
}

enum ProcessSortMode: String, CaseIterable, Identifiable {
    case `default` = "默认"
    case cpu = "CPU"
    case memory = "内存"

    var id: String { rawValue }
}

struct ProcessSection: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let rows: [ProcessRowItem]
}

struct ProcessRowItem: Identifiable {
    let process: DevProcess
    let depth: Int

    var id: Int32 { process.pid }
}

@MainActor
final class ProcessStore: ObservableObject {
    static let autoRefreshInterval: TimeInterval = 3
    static let highCPUThreshold: Double = 50

    @Published var processes: [DevProcess] = []
    @Published var selectedPIDs: Set<Int32> = []
    @Published var query = ""
    @Published var viewMode: ProcessViewMode = .source
    @Published var sortMode: ProcessSortMode = .default
    @Published var isRefreshing = false
    @Published var lastActionSummary: String?
    @Published var lastScanError: String?
    @Published private(set) var hasLoadedOnce = false

    private let scanner: any ProcessScanning
    private let controller: ProcessController
    private var refreshTimer: Timer?
    private var previousSamples: [Int32: CPUSampler.Sample] = [:]

    init(scanner: any ProcessScanning = ProcessScanner(), controller: ProcessController = ProcessController()) {
        self.scanner = scanner
        self.controller = controller
    }

    var selectedCount: Int {
        selectedPIDs.count
    }

    var canStopSelected: Bool {
        processes.contains { selectedPIDs.contains($0.pid) && $0.safety != .protected }
    }

    var hasWarnSelected: Bool {
        warnSelectedCount > 0
    }

    var warnSelectedCount: Int {
        processes.filter { selectedPIDs.contains($0.pid) && $0.safety == .warn }.count
    }

    var filteredProcesses: [DevProcess] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else {
            return processes
        }

        return processes.filter { process in
            let searchable = [
                process.projectName,
                process.source.displayName,
                process.kind.displayName,
                process.safety.displayName,
                process.executableName,
                process.commandLine,
                ProcessDisplayFormatter.resourceSummary(for: process),
                String(process.pid),
                process.listeningPorts.map { ":\($0)" }.joined(separator: " "),
                process.listeningPortDetails
                    .map {
                        "\($0.endpoint) \(PortCategory.classify(port: $0, processKind: process.kind).displayName)"
                    }
                    .joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()

            return searchable.contains(trimmedQuery)
        }
    }

    var sections: [ProcessSection] {
        switch viewMode {
        case .source:
            return sectionsBySource()
        case .project:
            return sectionsByProject()
        case .port:
            return sectionsByPort()
        }
    }

    func refresh() {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        let scanner = scanner

        Task.detached(priority: .userInitiated) {
            let result = scanner.scanDetailed()

            await MainActor.run {
                let now = Date()
                let enriched = result.processes.map { process -> DevProcess in
                    var copy = process
                    copy.instantaneousCPUPercent = CPUSampler.instantaneousCPU(
                        previous: self.previousSamples[process.pid],
                        currentCPUTime: process.raw.cpuTimeSeconds,
                        startedAt: process.raw.startedAt,
                        now: now
                    )
                    return copy
                }

                self.processes = enriched
                self.previousSamples = Dictionary(
                    uniqueKeysWithValues: enriched.map { process in
                        (
                            process.pid,
                            CPUSampler.Sample(
                                cpuTimeSeconds: process.raw.cpuTimeSeconds,
                                wallClock: now,
                                startedAt: process.raw.startedAt
                            )
                        )
                    }
                )
                self.selectedPIDs = self.selectedPIDs.intersection(Set(enriched.map(\.pid)))
                self.lastScanError = Self.scanErrorSummary(for: result.errors, processCount: result.processes.count)
                self.isRefreshing = false
                self.hasLoadedOnce = true
            }
        }
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.autoRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func toggleSelection(for pid: Int32) {
        if selectedPIDs.contains(pid) {
            selectedPIDs.remove(pid)
        } else if let process = processes.first(where: { $0.pid == pid }), process.safety != .protected {
            selectedPIDs.insert(pid)
        }
    }

    func selectChildrenOfSelectedProcesses() {
        let childrenByParent = Dictionary(grouping: processes, by: \.ppid)
        var expanded = selectedPIDs
        var stack = Array(selectedPIDs)

        while let parent = stack.popLast() {
            for child in childrenByParent[parent, default: []] where child.safety != .protected {
                if !expanded.contains(child.pid) {
                    expanded.insert(child.pid)
                    stack.append(child.pid)
                }
            }
        }

        selectedPIDs = expanded
    }

    func stopSelected() {
        let targets = selectedActionableProcesses()
        let results = targets.map { controller.stop(process: $0) }
        summarize(results, verb: "停止")
        refresh()
    }

    func forceKillSelected() {
        let targets = selectedActionableProcesses()
        let results = targets.map { controller.forceKill(process: $0) }
        summarize(results, verb: "强制结束")
        refresh()
    }

    private func selectedActionableProcesses() -> [DevProcess] {
        processes
            .filter { selectedPIDs.contains($0.pid) && $0.safety != .protected }
            .sorted { $0.pid < $1.pid }
    }

    private func summarize(_ results: [ProcessActionResult], verb: String) {
        let succeeded = results.filter(\.succeeded).count
        let failed = results.count - succeeded

        if failed == 0 {
            lastActionSummary = "\(verb) \(succeeded) 个进程"
        } else {
            let failedActionDetails = results
                .filter { !$0.succeeded }
                .map { "PID \($0.pid)：\($0.errorMessage ?? "未知错误")" }
                .joined(separator: "；")
            lastActionSummary = "\(verb) \(succeeded) 个进程，\(failed) 个失败：\(failedActionDetails)"
        }
    }

    private static func scanErrorSummary(for errors: [String], processCount: Int) -> String? {
        guard !errors.isEmpty else {
            return nil
        }

        let detail = errors.joined(separator: "；")
        if processCount == 0, errors.contains(where: { $0.hasPrefix("ps:") }) {
            return "扫描失败：无法读取进程列表：\(detail)"
        }

        return "部分扫描信息不可用：\(detail)"
    }

    private func sectionsBySource() -> [ProcessSection] {
        ProcessSource.allCases.compactMap { source in
            let items = filteredProcesses.filter { $0.source == source }
            guard !items.isEmpty else { return nil }

            return ProcessSection(
                id: source.rawValue,
                title: source.displayName,
                subtitle: "\(items.count) 个进程",
                rows: rows(for: items)
            )
        }
    }

    private func sectionsByProject() -> [ProcessSection] {
        let grouped = Dictionary(grouping: filteredProcesses, by: \.projectName)
        return grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .compactMap { project in
                guard let items = grouped[project], !items.isEmpty else { return nil }
                let sources = Set(items.map(\.source.displayName)).sorted().joined(separator: " / ")
                return ProcessSection(
                    id: project,
                    title: project,
                    subtitle: sources.isEmpty ? "\(items.count) 个进程" : "\(items.count) 个进程 · \(sources)",
                    rows: rows(for: items.sorted { $0.pid < $1.pid })
                )
            }
    }

    private func sectionsByPort() -> [ProcessSection] {
        PortCategory.allCases
            .sorted { $0.priority < $1.priority }
            .compactMap { category in
                let filtered = filteredProcesses
                    .filter { portCategories(for: $0).contains(category) }
                let items = sortMode == .default
                    ? filtered.sorted { lhs, rhs in
                        let lhsPort = firstPort(in: category, for: lhs) ?? Int.max
                        let rhsPort = firstPort(in: category, for: rhs) ?? Int.max
                        if lhsPort != rhsPort {
                            return lhsPort < rhsPort
                        }
                        return lhs.pid < rhs.pid
                    }
                    : filtered.sorted { sortMetric(for: $0) > sortMetric(for: $1) }

                guard !items.isEmpty else {
                    return nil
                }

                let portCount = items.reduce(0) { partialResult, process in
                    partialResult + process.listeningPortDetails.filter {
                        PortCategory.classify(port: $0, processKind: process.kind) == category
                    }.count
                }

                return ProcessSection(
                    id: "port-\(category.rawValue)",
                    title: category.displayName,
                    subtitle: "\(portCount) 个端口 · \(items.count) 个进程",
                    rows: items.map { ProcessRowItem(process: $0, depth: 0) }
                )
            }
    }

    private func sortMetric(for process: DevProcess) -> Double {
        switch sortMode {
        case .default:
            return 0
        case .cpu:
            return process.instantaneousCPUPercent ?? process.cpuPercent
        case .memory:
            return process.memoryPercent
        }
    }

    private func rows(for items: [DevProcess]) -> [ProcessRowItem] {
        guard sortMode != .default else {
            return treeRows(for: items)
        }
        return items
            .sorted { sortMetric(for: $0) > sortMetric(for: $1) }
            .map { ProcessRowItem(process: $0, depth: 0) }
    }

    private func treeRows(for items: [DevProcess]) -> [ProcessRowItem] {
        let processIDs = Set(items.map(\.pid))
        let childrenByParent = Dictionary(grouping: items, by: \.ppid)
        let roots = items
            .filter { !processIDs.contains($0.ppid) }
            .sorted { lhs, rhs in
                if lhs.projectName != rhs.projectName {
                    return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
                }
                return lhs.pid < rhs.pid
            }

        var rows: [ProcessRowItem] = []
        var visited: Set<Int32> = []

        func append(_ process: DevProcess, depth: Int) {
            guard !visited.contains(process.pid) else {
                return
            }

            visited.insert(process.pid)
            rows.append(ProcessRowItem(process: process, depth: depth))

            for child in childrenByParent[process.pid, default: []].sorted(by: { $0.pid < $1.pid }) {
                append(child, depth: depth + 1)
            }
        }

        for root in roots {
            append(root, depth: 0)
        }

        for orphan in items.sorted(by: { $0.pid < $1.pid }) where !visited.contains(orphan.pid) {
            append(orphan, depth: 0)
        }

        return rows
    }

    private func portCategories(for process: DevProcess) -> Set<PortCategory> {
        Set(process.listeningPortDetails.map {
            PortCategory.classify(port: $0, processKind: process.kind)
        })
    }

    private func firstPort(in category: PortCategory, for process: DevProcess) -> Int? {
        process.listeningPortDetails
            .filter { PortCategory.classify(port: $0, processKind: process.kind) == category }
            .map(\.port)
            .min()
    }
}
