import SwiftUI

struct PortsView: View {
    @Environment(\.metrics) private var metrics
    let items: [ListeningPort]
    let selectedID: ListeningPort.ID?
    let scroll: ScrollIntent
    let onSelect: (ListeningPort) -> Void
    let onActivate: (ListeningPort) -> Void
    let onActions: (ListeningPort) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        Row(item: item, selected: item.id == selectedID)
                            .selectionFrame(item.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { onActivate(item) }
                            .onTapGesture { onSelect(item) }
                            .onRightClick { onActions(item) }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: selectedID == items.first?.id, proxy: proxy)
        }
    }

    private struct Row: View {
        @Environment(\.metrics) private var metrics
        let item: ListeningPort
        let selected: Bool
        @State private var hovered = false

        var body: some View {
            HStack(spacing: metrics.spacing.lg) {
                Image(systemName: "network")
                    .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
                Text(":\(item.port)").font(metrics.typography.rowTitle)
                Text([item.command, item.directoryName].compactMap { $0 }.joined(separator: " · "))
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: metrics.spacing.md)
                Text(String(item.pid))
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, metrics.spacing.md)
            .padding(.vertical, metrics.spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                    .fill(selected ? Theme.Colors.selection : hovered ? Theme.Colors.rowHover : .clear)
            )
            .armedHover($hovered)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Port \(item.port), \(item.command), PID \(item.pid)")
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}
