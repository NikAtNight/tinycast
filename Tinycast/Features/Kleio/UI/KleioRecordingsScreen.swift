import SwiftUI

struct KleioRecordingsScreen: PaletteScreen {
    let store: KleioStore
    let coordinator: KleioCoordinator
    let vm: PaletteState
    let openActions: () -> Void

    let primaryActionTitle = "Copy Transcript"

    var rows: [KleioRecording] { KleioQuery.rank(store.recordings, for: vm.query) }

    func activate(at selection: Int) {
        guard rows.indices.contains(selection) else { return }
        coordinator.copy(rows[selection].text)
    }

    func secondary(at selection: Int) -> Bool {
        guard rows.indices.contains(selection) else { return false }
        coordinator.copy(rows[selection].text)
        return true
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard rows.indices.contains(selection) else { return nil }
        let recording = rows[selection]
        var items = [
            PopoverMenuItem(title: primaryActionTitle, systemImage: "doc.on.clipboard", shortcut: "↵") {
                coordinator.copy(recording.text)
            },
            PopoverMenuItem(title: "Show in Finder", systemImage: "folder") { coordinator.reveal(recording) }
        ]
        if !recording.segments.isEmpty {
            items.append(PopoverMenuItem(title: "Copy Segment Range", systemImage: "text.quote") {
                coordinator.segmentRecordingID = recording.id
            })
        }
        return PopoverMenuContent(header: recording.title, items: items)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(KleioRecordingsView(
            recordings: rows, store: store, selection: selection,
            scroll: scroll, vm: vm, openActions: openActions
        ).environment(coordinator))
    }
}
