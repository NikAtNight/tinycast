import SwiftUI

struct TranscriptsScreen: PaletteScreen {
    let store: TranscriptStore
    let coordinator: TranscriptsCoordinator
    let vm: PaletteState
    let source: TranscriptEntry.Source
    let openActions: () -> Void

    var rows: [TranscriptEntry] { TranscriptQuery.rank(store.entries.filter { $0.source == source }, for: vm.query) }
    var primaryActionTitle: String { source == .dictation ? "Paste Dictation" : "Copy Transcript" }

    func activate(at selection: Int) {
        guard rows.indices.contains(selection) else { return }
        coordinator.activate(rows[selection])
    }

    func secondary(at selection: Int) -> Bool {
        guard rows.indices.contains(selection) else { return false }
        coordinator.copy(rows[selection].text)
        return true
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard rows.indices.contains(selection) else { return nil }
        let entry = rows[selection]
        var items = [
            PopoverMenuItem(title: primaryActionTitle, systemImage: "doc.on.clipboard", shortcut: "↵") {
                coordinator.activate(entry)
            },
            PopoverMenuItem(title: "Show in Finder", systemImage: "folder") { coordinator.reveal(entry) }
        ]
        if source == .dictation {
            items.append(PopoverMenuItem(title: "Copy Dictation", systemImage: "doc.on.doc", shortcut: "⌘↵") {
                coordinator.copy(entry.text)
            })
        } else if !entry.segments.isEmpty {
            items.append(PopoverMenuItem(title: "Copy Segment Range", systemImage: "text.quote") {
                coordinator.segmentEntryID = entry.id
            })
        }
        return PopoverMenuContent(header: source == .dictation ? "Dictation" : entry.title, items: items)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(TranscriptsView(
            entries: rows, store: store, source: source, selection: selection,
            scroll: scroll, vm: vm, openActions: openActions
        ).environment(coordinator))
    }
}
