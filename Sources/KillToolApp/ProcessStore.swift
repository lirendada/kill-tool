import Combine
import Foundation
import KillToolCore

enum ProcessViewMode: String, CaseIterable, Identifiable {
    case source = "来源"
    case project = "项目"

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
    static let autoRefreshInterval: TimeInterval = 60

    @Published var processes: [DevProcess] = []
    @Published var selectedPIDs: Set<Int32> = []
    @Published var query = ""
    @Published var viewMode: ProcessViewMode = .source
    @Published var isRefreshing = false
    @Published var lastActionSummary: String?
    @Published var lastScanError: String?

    private let scanner: ProcessScanner
    private let controller: ProcessController
    private var refreshTimer: Timer?

    init(scanner: ProcessScanner = ProcessScanner(), controller: ProcessController = ProcessController()) {
        self.scanner = scanner
        self.controller = controller
    }

    var selectedCount: Int {
        selectedPIDs.count
    }

    var canStopSelected: Bool {
        processes.contains { selectedPIDs.contains($0.pid) && $0.safety != .protected }
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
                process.listeningPorts.map { ":\($0)" }.joined(separator: " ")
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
        }
    }

    func refresh() {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        let currentUser = scanner.currentUser

        Task.detached(priority: .userInitiated) { [currentUser] in
            let result = ProcessScanner(currentUser: currentUser).scanDetailed()

            await MainActor.run {
                self.processes = result.processes
                self.selectedPIDs = self.selectedPIDs.intersection(Set(result.processes.map(\.pid)))
                self.lastScanError = result.errors.isEmpty ? nil : "扫描部分失败：\(result.errors.joined(separator: "；"))"
                self.isRefreshing = false
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
        let results = targets.map { controller.stop(pid: $0.pid) }
        summarize(results, verb: "停止")
        refresh()
    }

    func forceKillSelected() {
        let targets = selectedActionableProcesses()
        let results = targets.map { controller.forceKill(pid: $0.pid) }
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
            lastActionSummary = "\(verb) \(succeeded) 个进程，\(failed) 个失败"
        }
    }

    private func sectionsBySource() -> [ProcessSection] {
        ProcessSource.allCases.compactMap { source in
            let items = filteredProcesses.filter { $0.source == source }
            guard !items.isEmpty else { return nil }

            return ProcessSection(
                id: source.rawValue,
                title: source.displayName,
                subtitle: "\(items.count) 个进程",
                rows: treeRows(for: items)
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
                    rows: treeRows(for: items.sorted { $0.pid < $1.pid })
                )
            }
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
}
