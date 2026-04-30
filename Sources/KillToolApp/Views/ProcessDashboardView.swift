import KillToolCore
import SwiftUI

struct ProcessDashboardView: View {
    @ObservedObject var store: ProcessStore
    @State private var showForceKillConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            actionBar
        }
        .frame(width: 520, height: 680)
        .background(.regularMaterial)
        .onAppear {
            store.refresh()
            store.startAutoRefresh()
        }
        .onDisappear {
            store.stopAutoRefresh()
        }
        .confirmationDialog(
            "强制结束已选进程？",
            isPresented: $showForceKillConfirmation,
            titleVisibility: .visible
        ) {
            Button("强制结束", role: .destructive) {
                store.forceKillSelected()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将向 \(store.selectedCount) 个已勾选进程发送 SIGKILL。")
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("开发进程")
                        .font(.system(size: 20, weight: .semibold))
                    Text("\(store.processes.count) 个进程 · 已选 \(store.selectedCount) 个")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    store.refresh()
                } label: {
                    Image(systemName: store.isRefreshing ? "arrow.triangle.2.circlepath.circle" : "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新")
            }

            HStack(spacing: 8) {
                Picker("", selection: $store.viewMode) {
                    ForEach(ProcessViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                TextField("搜索进程、端口或项目", text: $store.query)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(16)
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if store.sections.isEmpty {
                    emptyState
                } else {
                    ForEach(store.sections) { section in
                        ProcessSectionView(section: section, store: store)
                    }
                }
            }
            .padding(12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("没有匹配的开发进程")
                .font(.system(size: 13, weight: .medium))
            Text("打开 Claude Code、Codex、VS Code 或 Terminal 后会自动刷新。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private var actionBar: some View {
        VStack(spacing: 8) {
            if let summary = store.lastActionSummary {
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Button("停止所选") {
                    store.stopSelected()
                }
                .disabled(!store.canStopSelected)

                Button("强制结束") {
                    showForceKillConfirmation = true
                }
                .disabled(!store.canStopSelected)
                .keyboardShortcut(.delete, modifiers: [.command])

                Button("选择子进程") {
                    store.selectChildrenOfSelectedProcesses()
                }
                .disabled(store.selectedCount == 0)

                Spacer()

                Text("只会停止已勾选的进程")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }
}
