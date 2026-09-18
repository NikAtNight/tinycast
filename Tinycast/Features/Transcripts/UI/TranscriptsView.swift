import SwiftUI

struct TranscriptsView: View {
    @Environment(TranscriptsCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    let entries: [TranscriptEntry]
    let store: TranscriptStore
    let source: TranscriptEntry.Source
    let selection: Int
    let scroll: ScrollIntent
    let vm: PaletteState
    let openActions: () -> Void

    private var selected: TranscriptEntry? {
        entries.indices.contains(selection) ? entries[selection] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if let issue = store.issue {
                Text(issue).font(metrics.typography.rowTrailing).foregroundStyle(Theme.Colors.textSecondary)
                    .padding(metrics.spacing.md)
            }
            if entries.isEmpty {
                EmptyResults(text: vm.query.isEmpty ? "No transcripts found" : "No matching transcripts")
            } else {
                HStack(spacing: 0) {
                    list
                        .frame(width: metrics.size.clipboardListWidth)
                    Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                    if let selected {
                        TranscriptPreview(
                            entry: selected, choosingRange: coordinator.segmentEntryID == selected.id
                        ).id(selected.id)
                    }
                }
            }
        }
        .task(id: "\(source)-\(vm.isVisible)") {
            guard vm.isVisible else { return }
            await store.observe(source)
        }
        .onChange(of: vm.isVisible) {
            if !vm.isVisible { coordinator.segmentEntryID = nil }
        }
        .onDisappear { coordinator.segmentEntryID = nil }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    SectionHeader(title: source == .dictation ? "Dictation History" : "Scribe Recordings", isFirst: true)
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        TranscriptRow(entry: entry, selected: entry.id == selected?.id)
                            .selectionFrame(entry.id == selected?.id)
                            .contentShape(Rectangle())
                            .onRowClick(select: { vm.selection = index }, activate: { coordinator.activate(entry) })
                            .onRightClick {
                                vm.selection = index
                                openActions()
                            }
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
            .scrollFollowsSelection(scroll, row: selected?.id, atOrigin: selection == 0, proxy: proxy)
        }
    }
}

private struct TranscriptRow: View {
    @Environment(\.metrics) private var metrics
    let entry: TranscriptEntry
    let selected: Bool
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            Text(entry.title).font(metrics.typography.rowTitle).lineLimit(2)
            HStack {
                Text(entry.date, format: .dateTime.year().month().day().hour().minute().second())
                if let duration = entry.duration {
                    Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                }
            }
            .font(metrics.typography.rowTrailing)
            .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(RoundedRectangle(cornerRadius: metrics.radius.row)
            .fill(selected ? Theme.Colors.selection : hovered ? Theme.Colors.rowHover : .clear))
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct TranscriptPreview: View {
    @Environment(TranscriptsCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    let entry: TranscriptEntry
    let choosingRange: Bool
    @State private var firstSegment = 0
    @State private var lastSegment = 0

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            if choosingRange {
                Stepper("First segment: \(firstSegment + 1)", value: $firstSegment, in: 0...lastSegment)
                Stepper("Last segment: \(lastSegment + 1)", value: $lastSegment,
                        in: firstSegment...max(0, entry.segments.count - 1))
                Button("Copy Range") {
                    if let text = entry.text(in: firstSegment...lastSegment) { coordinator.copy(text) }
                }
            }
            ScrollView {
                if choosingRange {
                    VStack(alignment: .leading, spacing: metrics.spacing.md) {
                        ForEach(Array(entry.segments.enumerated()), id: \.offset) { index, segment in
                            Text("\(index + 1). \(segment.text)")
                                .foregroundStyle((firstSegment...lastSegment).contains(index)
                                    ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                        }
                    }
                } else {
                    Text(entry.text.isEmpty ? "No transcript text" : entry.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .textSelection(.enabled)
            .edgeDissolve()
        }
        .font(metrics.typography.rowTitle)
        .padding(metrics.spacing.lg)
        .onAppear { lastSegment = max(0, entry.segments.count - 1) }
    }
}
