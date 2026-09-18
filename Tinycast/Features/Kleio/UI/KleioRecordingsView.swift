import SwiftUI

struct KleioRecordingsView: View {
    @Environment(KleioCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    let recordings: [KleioRecording]
    let store: KleioStore
    let selection: Int
    let scroll: ScrollIntent
    let vm: PaletteState
    let openActions: () -> Void

    private var selected: KleioRecording? {
        recordings.indices.contains(selection) ? recordings[selection] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if let issue = store.issue {
                Text(issue).font(metrics.typography.rowTrailing).foregroundStyle(Theme.Colors.textSecondary)
                    .padding(metrics.spacing.md)
            }
            if recordings.isEmpty {
                EmptyResults(text: vm.query.isEmpty ? "No recordings found" : "No matching recordings")
            } else {
                HStack(spacing: 0) {
                    list
                        .frame(width: metrics.size.clipboardListWidth)
                    Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                    if let selected {
                        KleioRecordingPreview(
                            recording: selected, choosingRange: coordinator.segmentRecordingID == selected.id
                        ).id(selected.id)
                    }
                }
            }
        }
        .task(id: vm.isVisible) {
            if vm.isVisible {
                await store.load()
            } else {
                store.release()
                coordinator.segmentRecordingID = nil
            }
        }
        .onDisappear {
            store.release()
            coordinator.segmentRecordingID = nil
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    SectionHeader(title: "Kleio Recordings", isFirst: true)
                    ForEach(Array(recordings.enumerated()), id: \.element.id) { index, recording in
                        KleioRecordingRow(recording: recording, selected: recording.id == selected?.id)
                            .selectionFrame(recording.id == selected?.id)
                            .contentShape(Rectangle())
                            .onRowClick(select: { vm.selection = index }, activate: { coordinator.copy(recording.text) })
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

private struct KleioRecordingRow: View {
    @Environment(\.metrics) private var metrics
    let recording: KleioRecording
    let selected: Bool
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            Text(recording.title).font(metrics.typography.rowTitle).lineLimit(2)
            HStack {
                Text(recording.date, format: .dateTime.year().month().day().hour().minute().second())
                Text(Duration.seconds(recording.duration).formatted(.time(pattern: .minuteSecond)))
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

private struct KleioRecordingPreview: View {
    @Environment(KleioCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    let recording: KleioRecording
    let choosingRange: Bool
    @State private var firstSegment = 0
    @State private var lastSegment = 0

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            if choosingRange {
                Stepper("First segment: \(firstSegment + 1)", value: $firstSegment, in: 0...lastSegment)
                Stepper("Last segment: \(lastSegment + 1)", value: $lastSegment,
                        in: firstSegment...max(0, recording.segments.count - 1))
                Button("Copy Range") {
                    if let text = recording.text(in: firstSegment...lastSegment) { coordinator.copy(text) }
                }
            }
            ScrollView {
                if choosingRange {
                    VStack(alignment: .leading, spacing: metrics.spacing.md) {
                        ForEach(Array(recording.segments.enumerated()), id: \.offset) { index, segment in
                            Text("\(index + 1). \(segment.text)")
                                .foregroundStyle((firstSegment...lastSegment).contains(index)
                                    ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                        }
                    }
                } else {
                    Text(recording.text.isEmpty ? "No transcript text" : recording.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .textSelection(.enabled)
            .edgeDissolve()
        }
        .font(metrics.typography.rowTitle)
        .padding(metrics.spacing.lg)
        .onAppear { lastSegment = max(0, recording.segments.count - 1) }
    }
}
