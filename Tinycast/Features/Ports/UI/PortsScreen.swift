import SwiftUI

struct PortsScreen: PaletteScreen {
    let session: PortsSession
    let coordinator: PortsCoordinator
    let vm: PaletteState
    let openActions: () -> Void

    var rows: [ListeningPort] {
        session.failure == nil ? PortsQuery.rank(session.ports, for: vm.query) : []
    }
    var primaryActionTitle: String { "Open in Browser" }

    private func item(at selection: Int) -> ListeningPort? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    func activate(at selection: Int) {
        guard let item = item(at: selection) else { return }
        coordinator.open(item)
    }

    func secondary(at selection: Int) -> Bool { false }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        if shortcut == .restart {
            coordinator.refresh()
            return true
        }
        guard shortcut == .delete, let item = item(at: selection) else { return false }
        coordinator.kill(item)
        return true
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let item = item(at: selection) else { return nil }
        var actions = [
            PopoverMenuItem(title: "Open in Browser", systemImage: "globe", shortcut: "↵") {
                coordinator.open(item)
            },
            PopoverMenuItem(title: "Copy Port", systemImage: "doc.on.clipboard", startsSection: true) {
                coordinator.copy(String(item.port))
            },
            PopoverMenuItem(title: "Copy PID", systemImage: "doc.on.clipboard") {
                coordinator.copy(String(item.pid))
            }
        ]
        if item.cwd != nil {
            actions += [
                PopoverMenuItem(title: "Reveal Working Directory", systemImage: "folder") {
                    coordinator.reveal(item)
                },
                PopoverMenuItem(title: "Open in Ghostty", systemImage: "terminal") {
                    coordinator.openInGhostty(item)
                }
            ]
        }
        actions += [
            PopoverMenuItem(
                title: "Refresh", systemImage: "arrow.clockwise", startsSection: true, shortcut: "⌘R"
            ) { coordinator.refresh() },
            PopoverMenuItem(
                title: "Kill Process", systemImage: "stop.circle", startsSection: true,
                shortcut: "⌃X", isDestructive: true
            ) { coordinator.kill(item) }
        ]
        return PopoverMenuContent(header: ":\(item.port) · \(item.command)", items: actions)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        if let failure = session.failure {
            return AnyView(EmptyResults(text: "\(failure) Press ⌘R to retry."))
        }
        if rows.isEmpty {
            return AnyView(
                EmptyResults(text: session.isScanning ? "Scanning ports…" : "No listening ports found"))
        }
        return AnyView(
            PortsView(
                items: rows, selectedID: item(at: selection)?.id, scroll: scroll,
                onSelect: { item in vm.selection = rows.firstIndex(of: item) ?? 0 },
                onActivate: { coordinator.open($0) },
                onActions: { item in
                    vm.selection = rows.firstIndex(of: item) ?? 0
                    openActions()
                }))
    }
}
