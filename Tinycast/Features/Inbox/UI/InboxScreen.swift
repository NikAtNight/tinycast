import SwiftUI

struct InboxScreen: PaletteScreen {
    let coordinator: InboxCoordinator
    let vm: PaletteState
    let openActions: () -> Void

    var rows: [InboxItem] { InboxItem.ordered(coordinator.store.items, query: vm.query) }
    var primaryActionTitle: String { "Open" }

    private func item(at selection: Int) -> InboxItem? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func activate(at selection: Int) {
        guard let item = item(at: selection) else { return }
        coordinator.open(item)
    }

    func secondary(at selection: Int) -> Bool {
        guard let item = item(at: selection) else { return false }
        coordinator.copyURL(item)
        return true
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let item = item(at: selection) else { return nil }
        var actions = [
            PopoverMenuItem(title: "Open", systemImage: "arrow.up.right", shortcut: "↵") {
                coordinator.open(item)
            },
            PopoverMenuItem(title: "Copy URL", systemImage: "link", shortcut: "⌘↵") {
                coordinator.copyURL(item)
            }
        ]
        if item.source == .github {
            actions.append(PopoverMenuItem(title: "Copy branch name", systemImage: "arrow.triangle.branch") {
                coordinator.copyBranch(item)
            })
        }
        actions.append(PopoverMenuItem(title: "Mark read", systemImage: "checkmark") {
            coordinator.markRead(item)
        })
        actions.append(PopoverMenuItem(title: "Refresh", systemImage: "arrow.clockwise", startsSection: true) {
            coordinator.refresh()
        })
        return PopoverMenuContent(header: item.title, items: actions)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            InboxView(
                rows: rows, selectedID: item(at: selection)?.id, scroll: scroll,
                onSelect: { item in vm.selection = rows.firstIndex(of: item) ?? 0 },
                onActivate: coordinator.open,
                onActions: { item in
                    vm.selection = rows.firstIndex(of: item) ?? 0
                    openActions()
                }
            ).environment(coordinator)
                .task(id: vm.isVisible) {
                    if vm.isVisible { coordinator.refresh() }
                }
        )
    }
}
