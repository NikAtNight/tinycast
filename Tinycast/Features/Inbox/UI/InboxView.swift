import SwiftUI

struct InboxView: View {
    @Environment(InboxCoordinator.self) private var coordinator
    private var store: InboxStore { coordinator.store }
    @Environment(\.metrics) private var metrics
    let rows: [InboxItem]
    let selectedID: String?
    let scroll: ScrollIntent
    let onSelect: (InboxItem) -> Void
    let onActivate: (InboxItem) -> Void
    let onActions: (InboxItem) -> Void

    private enum Row: Identifiable {
        case header(InboxItem.Section)
        case item(InboxItem)
        var id: String {
            switch self {
            case .header(let section): "header:\(section.rawValue)"
            case .item(let item): item.id
            }
        }
    }

    private var displayRows: [Row] {
        var result: [Row] = []
        var previous: InboxItem.Section?
        for item in rows {
            if item.section != previous { result.append(.header(item.section)) }
            result.append(.item(item))
            previous = item.section
        }
        return result
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if store.isLoading || store.isRefreshing {
                        Text("Refreshing Inbox...").font(metrics.typography.rowTrailing)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    ForEach(store.errors, id: \.self) { error in
                        Text(error).font(metrics.typography.rowTrailing)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    if !store.errors.isEmpty {
                        Button("Retry") { coordinator.refresh() }.buttonStyle(.plain)
                    }
                    if rows.isEmpty && !store.isLoading && !store.isRefreshing {
                        Text("No matching Inbox items").foregroundStyle(Theme.Colors.textSecondary)
                    }
                    ForEach(displayRows) { row in
                        switch row {
                        case .header(let section):
                            SectionHeader(title: section.rawValue, isFirst: row.id == displayRows.first?.id)
                        case .item(let item):
                            InboxRow(item: item, selected: item.id == selectedID,
                                     unread: item.isUnread(readThrough: store.preferences.readThrough))
                                .contentShape(Rectangle())
                                .onRowClick(select: { onSelect(item) }, activate: { onActivate(item) })
                                .onRightClick { onActions(item) }
                                .selectionFrame(item.id == selectedID)
                        }
                    }
                    if !store.jiraConnected {
                        Text("Connect Jira in Inbox settings to see assigned issues.")
                            .font(metrics.typography.rowTrailing)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .padding(.top, metrics.spacing.md)
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
            .scrollFollowsSelection(scroll, row: selectedID, atOrigin: selectedID == rows.first?.id, proxy: proxy)
        }
    }
}

private struct InboxRow: View {
    @Environment(\.metrics) private var metrics
    let item: InboxItem
    let selected: Bool
    let unread: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            SymbolImage(name: unread ? "envelope.badge" : "envelope.open", size: metrics.size.rowIcon * 0.7)
                .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
                .foregroundStyle(unread ? Theme.Colors.brand : Theme.Colors.textSecondary)
            VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                Text(item.title).font(metrics.typography.rowTitle).lineLimit(1)
                Text(item.subtitle).font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary).lineLimit(1)
            }
            Spacer(minLength: metrics.spacing.md)
            Text(item.state).font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textTertiary).lineLimit(1)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill))
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.subtitle), \(item.state), \(unread ? "unread" : "read")")
        .accessibilityAddTraits(.isButton)
    }
}
