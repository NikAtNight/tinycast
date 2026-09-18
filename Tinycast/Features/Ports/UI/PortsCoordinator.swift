import AppKit

@MainActor
final class PortsCoordinator {
    private unowned let core: AppCore
    private let session: PortsSession
    private var killTask: Task<Void, Never>?

    init(core: AppCore, session: PortsSession) {
        self.core = core
        self.session = session
    }

    func show() {
        session.refresh()
        core.paletteCoordinator.togglePalette(mode: .ports)
    }

    func refresh() { session.refresh() }

    func open(_ item: ListeningPort) {
        guard let url = URL(string: "http://localhost:\(item.port)") else { return }
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        if !NSWorkspace.shared.open(url) {
            core.showMessage("Couldn't open port \(item.port)", tone: .danger)
        }
    }

    func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        core.showMessage("Copied \(value)")
    }

    func reveal(_ item: ListeningPort) {
        guard let cwd = item.cwd else { return }
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)])
    }

    func openInGhostty(_ item: ListeningPort) {
        guard let cwd = item.cwd else { return }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty")
        else {
            core.showMessage("Ghostty is not installed", tone: .danger)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--working-directory=\(cwd)"]
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        Task { [weak self] in
            do {
                try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
            } catch {
                self?.core.showMessage(error.localizedDescription, tone: .danger)
            }
        }
    }

    func kill(_ item: ListeningPort) {
        guard killTask == nil else { return }
        killTask = Task { [weak self] in
            guard let self else { return }
            defer { killTask = nil }
            let confirmed = await core.confirm(
                title: "Kill \(item.command)?",
                message: "Stop PID \(item.pid) on port \(item.port) and every process in its group? "
                    + "Processes still running after 3 seconds will be force killed.",
                symbol: "stop.circle", confirmTitle: "Kill Process", tone: .danger)
            guard confirmed else { return }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try await PortScanner.kill(pid: item.pid)
                }.value
                core.showMessage("Stopped process group for PID \(item.pid)")
            } catch {
                core.showMessage(error.localizedDescription, tone: .danger)
            }
            session.refresh()
        }
    }
}
