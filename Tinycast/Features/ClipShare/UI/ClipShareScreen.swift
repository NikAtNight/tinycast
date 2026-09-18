import SwiftUI

struct ClipShareScreen: PaletteScreen {
    let coordinator: ClipShareCoordinator
    let vm: PaletteState
    let openActions: () -> Void

    var rows: [ClipShareVideo] {
        let query = vm.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return coordinator.videos.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                || $0.originalFilename.localizedCaseInsensitiveContains(query)
        }
    }

    var primaryActionTitle: String {
        guard rows.indices.contains(vm.selection) else { return "Copy Share URL" }
        return rows[vm.selection].status == .ready ? "Copy Share URL" : "Actions"
    }

    func hasPrimaryAction(at selection: Int) -> Bool {
        guard rows.indices.contains(selection) else { return false }
        return true
    }

    func activate(at selection: Int) {
        guard rows.indices.contains(selection) else { return }
        if rows[selection].status == .ready { coordinator.copy(rows[selection]) }
        else { openActions() }
    }

    func secondary(at selection: Int) -> Bool {
        guard rows.indices.contains(selection), rows[selection].status == .ready else { return false }
        coordinator.open(rows[selection])
        return true
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard rows.indices.contains(selection) else { return nil }
        let video = rows[selection]
        var items: [PopoverMenuItem] = []
        if video.status == .ready, video.shareUrl != nil {
            items += [
                PopoverMenuItem(title: "Copy Share URL", systemImage: "link", shortcut: "↵") {
                    coordinator.copy(video)
                },
                PopoverMenuItem(title: "Open", systemImage: "globe", shortcut: "⌘↵") {
                    coordinator.open(video)
                },
                PopoverMenuItem(title: "Revoke Share Link", systemImage: "link.badge.plus",
                                startsSection: true, isDestructive: true) { coordinator.revoke(video) }
            ]
        }
        items += [
            PopoverMenuItem(title: "Delete Video", systemImage: "trash", isDestructive: true) {
                coordinator.delete(video)
            },
            PopoverMenuItem(title: "Refresh", systemImage: "arrow.clockwise", startsSection: true) {
                coordinator.refresh()
            }
        ]
        return PopoverMenuContent(header: video.title, items: items)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            ClipShareView(videos: rows, selection: selection, scroll: scroll, onSelect: { vm.selection = $0 },
                          openActions: openActions)
                .environment(coordinator))
    }
}
