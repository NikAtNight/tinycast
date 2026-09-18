import SwiftUI

struct TalixList: View {
    @Environment(TalixCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    let rows: [TalixScreen.Row]
    let selection: Int
    let scroll: ScrollIntent
    let onActivate: (Int) -> Void
    let onActions: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: metrics.spacing.xs) {
                    if !coordinator.hasKey {
                        Text("Add your API key in Settings > Talix to load projects.")
                            .font(metrics.typography.rowTrailing).foregroundStyle(.secondary)
                    }
                    if let error = coordinator.store.errorMessage {
                        Text(error).font(metrics.typography.rowTrailing).foregroundStyle(.secondary)
                    }
                    if coordinator.store.isLoading { ProgressView().controlSize(.small) }
                    SectionHeader(title: coordinator.pickingProject ? "Choose a project" : total, isFirst: true)
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        TalixRow(row: row, selected: index == selection,
                                 activate: { onActivate(index) })
                            .id(row.id)
                            .contentShape(Rectangle())
                            .onTapGesture { onActivate(index) }
                            .onRightClick { onActions(index) }
                            .selectionFrame(index == selection)
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
            .scrollFollowsSelection(scroll, row: rows.indices.contains(selection) ? rows[selection].id : nil,
                                    atOrigin: selection == 0, proxy: proxy)
        }
    }

    private var total: String {
        "Today · " + TalixTimeEntry.durationLabel(coordinator.store.entries.reduce(0) { $0 + $1.entry.duration })
    }
}

private struct TalixRow: View {
    @Environment(TalixCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    let row: TalixScreen.Row
    let selected: Bool
    let activate: () -> Void
    @State private var hovered = false

    var body: some View {
        Group {
            switch row {
            case .timer(let running):
                VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                    HStack {
                        Image(systemName: "timer")
                        Text(running.timer.projectName).font(metrics.typography.rowTitle)
                        Spacer()
                        if let entry = running.pendingEntry {
                            Text("Ready to log · " + TalixTimeEntry.durationLabel(entry.duration))
                        } else {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(TalixTimeEntry.durationLabel(context.date.timeIntervalSince(running.timer.startedAt)))
                                    .monospacedDigit()
                            }
                        }
                    }
                    HStack {
                        Text(running.environment.title).foregroundStyle(.secondary)
                        Spacer()
                        Button("Stop and Log", action: coordinator.stopTimer)
                        Button("Discard", action: coordinator.discardTimer)
                    }
                    .settingsEnabled(!coordinator.isBusy)
                }
            case .project(let project):
                HStack {
                    Image(systemName: "folder")
                    Text(project.name)
                    Spacer()
                    Text(project.client?.name ?? "").foregroundStyle(.secondary)
                }
            case .entry(let item):
                HStack {
                    Image(systemName: "clock")
                    VStack(alignment: .leading) {
                        Text(item.entry.description).lineLimit(1)
                        Text(item.project.name).font(metrics.typography.rowTrailing).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(TalixTimeEntry.durationLabel(item.entry.duration))
                }
            case .log:
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Log time")
                    Spacer()
                    Text("1.5 · 1h30 · 90m · 9-11 yesterday")
                        .font(metrics.typography.rowTrailing).foregroundStyle(.secondary)
                }
            }
        }
        .font(metrics.typography.rowTitle)
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(RoundedRectangle(cornerRadius: metrics.radius.row).fill(fill))
        .armedHover($hovered)
        .accessibilityElement(children: .contain)
    }

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        if case .timer = row { return Theme.Colors.cardFill }
        return .clear
    }
}
