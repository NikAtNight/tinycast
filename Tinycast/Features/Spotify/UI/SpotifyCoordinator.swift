import AppKit

@MainActor
@Observable
final class SpotifyCoordinator {
    let store: SpotifyStore
    let session: SpotifySearchSession
    private unowned let core: AppCore
    /// Test Connection's inline verdict; the pane clears it on the way out.
    private(set) var connectionReport: String?
    private(set) var connectionSucceeded = false
    private(set) var isBusy = false
    @ObservationIgnored private var actionTask: Task<Void, Never>?
    @ObservationIgnored private var settingsTask: Task<Void, Never>?

    init(store: SpotifyStore, session: SpotifySearchSession, core: AppCore) {
        self.store = store
        self.session = session
        self.core = core
    }

    isolated deinit {
        actionTask?.cancel()
        settingsTask?.cancel()
    }

    /// `query` is the fallback row's: the screen opens already searching what was typed.
    func show(query: String = "") {
        core.paletteCoordinator.togglePalette(mode: .spotify, seeding: query.isEmpty ? nil : query)
    }

    func play(_ item: SpotifyItem) {
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        actionTask?.cancel()
        actionTask = Task { [weak self] in
            guard let self else { return }
            let played = await SpotifyPlayer.play(uri: item.uri)
            guard !Task.isCancelled, !played else { return }
            core.showMessage("Spotify could not play \(item.name)", tone: .danger)
        }
    }

    func open(_ item: SpotifyItem) {
        guard let url = URL(string: item.uri) else { return }
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        NSWorkspace.shared.open(url)
    }

    func copyLink(_ item: SpotifyItem) {
        Paster.copyString(item.externalURL.absoluteString)
        core.showMessage("Copied Spotify link")
    }

    func copyURI(_ item: SpotifyItem) {
        Paster.copyString(item.uri)
        core.showMessage("Copied Spotify URI")
    }

    func openSettings() {
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        core.settingsCoordinator.showSettings(tab: .spotify)
    }

    func saveCredentials(clientID: String, clientSecret: String) {
        run {
            try await self.store.saveCredentials(clientID: clientID, clientSecret: clientSecret)
            self.session.reset()
            self.connectionReport = nil
            self.core.showMessage("Spotify credentials saved")
        }
    }

    func removeCredentials() {
        run {
            try await self.store.removeCredentials()
            self.session.reset()
            self.connectionReport = nil
            self.core.showMessage("Spotify credentials removed")
        }
    }

    func testConnection() {
        run {
            do {
                try await self.store.testConnection()
                self.connectionSucceeded = true
                self.connectionReport = "Connected to Spotify."
            } catch let error as SpotifySearchError {
                self.connectionSucceeded = false
                self.connectionReport = error.message
            }
        }
    }

    func clearReport() {
        connectionReport = nil
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true
        settingsTask = Task { [weak self] in
            defer { self?.isBusy = false }
            do {
                try await action()
            } catch {
                let message = (error as? SpotifySearchError)?.message ?? "Keychain refused the change."
                self?.core.showMessage(message, tone: .danger)
            }
        }
    }
}
