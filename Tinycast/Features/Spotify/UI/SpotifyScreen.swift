import SwiftUI

struct SpotifyScreen: PaletteScreen {
    let coordinator: SpotifyCoordinator
    let vm: PaletteState
    let openActions: () -> Void

    let primaryActionTitle = "Play"

    var rows: [SpotifyItem] { coordinator.session.results.all }

    private func row(at selection: Int) -> SpotifyItem? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    func activate(at selection: Int) {
        guard let item = row(at: selection) else { return }
        coordinator.play(item)
    }

    func secondary(at selection: Int) -> Bool {
        guard let item = row(at: selection) else { return false }
        coordinator.open(item)
        return true
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let item = row(at: selection) else { return nil }
        return PopoverMenuContent(header: item.name, items: [
            PopoverMenuItem(title: primaryActionTitle, systemImage: "play.fill", shortcut: "↵") {
                coordinator.play(item)
            },
            PopoverMenuItem(title: "Open in Spotify", systemImage: "arrow.up.forward.app", shortcut: "⌘↵") {
                coordinator.open(item)
            },
            PopoverMenuItem(title: "Copy Spotify Link", systemImage: "link", startsSection: true) {
                coordinator.copyLink(item)
            },
            PopoverMenuItem(title: "Copy URI", systemImage: "doc.on.doc") {
                coordinator.copyURI(item)
            }
        ])
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            SpotifyView(rows: rows, selection: selection, scroll: scroll, vm: vm, openActions: openActions)
                .environment(coordinator))
    }
}
