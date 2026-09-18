import AppKit

@MainActor
@Observable
final class InboxCoordinator {
    let store: InboxStore
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private var actionTask: Task<Void, Never>?

    init(store: InboxStore, core: AppCore) {
        self.store = store
        self.core = core
    }

    isolated deinit { actionTask?.cancel() }

    func refresh() { store.refreshNow() }

    func show() {
        core.paletteCoordinator.togglePalette(mode: .inbox)
    }

    func open(_ item: InboxItem) {
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        guard NSWorkspace.shared.open(item.url) else {
            core.showMessage("Could not open the Inbox link", tone: .danger)
            return
        }
    }

    func copyURL(_ item: InboxItem) {
        Paster.copyPlainText(item.url.absoluteString)
        core.showMessage("Copied URL")
    }

    func copyBranch(_ item: InboxItem) {
        guard item.source == .github else { return }
        perform { [weak self] in
            guard let self else { return }
            let branch = try await store.branch(for: item)
            Paster.copyPlainText(branch)
            core.showMessage("Copied branch name")
        }
    }

    func markRead(_ item: InboxItem) {
        perform { [weak self] in
            guard let self else { return }
            try await store.markRead(item)
            core.showMessage("Marked read in Tinycast")
        }
    }

    func save(organizations: String, refreshMinutes: Int) async -> Bool {
        do {
            try await store.save(organizations: organizations, refreshMinutes: refreshMinutes)
            core.showMessage("Inbox settings saved")
            return true
        } catch {
            core.showMessage("Could not save Inbox settings: \(error.localizedDescription)", tone: .danger)
            return false
        }
    }

    func connectJira(site: String, email: String, token: String) async -> Bool {
        do {
            try await store.connectJira(site: site, email: email, token: token)
            core.showMessage("Jira connection saved")
            return true
        } catch {
            core.showMessage("Could not save Jira connection: \(error.localizedDescription)", tone: .danger)
            return false
        }
    }

    func disconnectJira() async {
        do { try await store.disconnectJira() } catch { core.showMessage("Could not remove Jira connection", tone: .danger) }
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard actionTask == nil else { return }
        actionTask = Task { [weak self] in
            defer { self?.actionTask = nil }
            do { try await action() } catch { self?.core.showMessage(error.localizedDescription, tone: .danger) }
        }
    }
}
