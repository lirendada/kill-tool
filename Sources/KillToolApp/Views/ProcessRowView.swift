import KillToolCore
import SwiftUI

struct ProcessSectionView: View {
    let section: ProcessSection
    @ObservedObject var store: ProcessStore
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(section.title)
                        .font(.system(size: 14, weight: .semibold))

                    Spacer()

                    Text(section.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(section.rows) { row in
                        ProcessRowView(item: row, store: store)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ProcessRowView: View {
    let item: ProcessRowItem
    @ObservedObject var store: ProcessStore

    private var process: DevProcess {
        item.process
    }

    var body: some View {
        HStack(spacing: 8) {
            if item.depth > 0 {
                Rectangle()
                    .fill(Color.secondary.opacity(0.24))
                    .frame(width: 1, height: 28)
                    .padding(.leading, CGFloat(item.depth) * 14)
            }

            Toggle("", isOn: binding)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(process.safety == .protected)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(commandSummary)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .lineLimit(1)

                    if let portSummary {
                        Text(portSummary)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.blue)
                    }

                    Spacer(minLength: 6)

                    badge(process.kind.displayName, color: .blue)
                    safetyBadge
                }

                HStack(spacing: 8) {
                    Text(process.projectName)
                    Text("PID \(process.pid)")
                    Text(runtimeText)
                    Text(process.source.displayName)
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { store.selectedPIDs.contains(process.pid) },
            set: { _ in store.toggleSelection(for: process.pid) }
        )
    }

    private var commandSummary: String {
        let line = process.commandLine
        if line.count <= 58 {
            return line
        }
        return String(line.prefix(55)) + "..."
    }

    private var portSummary: String? {
        guard !process.listeningPorts.isEmpty else {
            return nil
        }
        return process.listeningPorts.map { ":\($0)" }.joined(separator: ", ")
    }

    private var runtimeText: String {
        let seconds = max(0, Int(Date().timeIntervalSince(process.raw.startedAt)))
        if seconds < 60 {
            return "\(seconds)s"
        }
        if seconds < 3600 {
            return "\(seconds / 60)m"
        }
        if seconds < 86_400 {
            return "\(seconds / 3600)h"
        }
        return "\(seconds / 86_400)d"
    }

    private var rowBackground: some ShapeStyle {
        if store.selectedPIDs.contains(process.pid) {
            return AnyShapeStyle(Color.accentColor.opacity(0.12))
        }
        return AnyShapeStyle(Color(nsColor: .textBackgroundColor).opacity(0.45))
    }

    private var safetyBadge: some View {
        let color: Color = switch process.safety {
        case .safe: .green
        case .warn: .orange
        case .protected: .gray
        }
        return badge(process.safety.displayName, color: color)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
