import Foundation

@MainActor
@Observable
final class InboxStore {
    private struct Snapshot: Codable, Sendable {
        let scope: UUID
        let items: [InboxItem]
        let fetchedAt: Date
    }

    private struct SavedPreferences: Codable, Sendable {
        var preferences = InboxPreferences()
        var scope = UUID()
    }

    private(set) var preferences = InboxPreferences()
    private(set) var items: [InboxItem] = []
    private(set) var isRefreshing = false
    private(set) var isLoading = true
    private(set) var errors: [String] = []
    private(set) var jiraSite = ""
    private(set) var jiraEmail = ""
    private(set) var jiraConnected = false
    private(set) var refreshedAt: Date?

    @ObservationIgnored private var scope = UUID()
    @ObservationIgnored private var credentialError: String?
    @ObservationIgnored private var credentials: JiraInboxSource.Credentials?
    @ObservationIgnored private var executable: URL?
    @ObservationIgnored private var pump: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var cacheURL: URL?
    @ObservationIgnored private var preferencesURL: URL?
    private let secrets = KeychainSecretStore(scope: "inbox-jira")
    private let account = UUID(uuidString: "8D50FA20-39DB-47BA-AAD7-427B3CE84A56")!

    isolated deinit {
        pump?.cancel()
        refreshTask?.cancel()
        saveTask?.cancel()
    }

    func start() {
        guard pump == nil else { return }
        pump = Task { [weak self] in
            await self?.load()
            while !Task.isCancelled {
                await self?.refresh()
                let minutes = self?.preferences.refreshMinutes ?? 5
                try? await Task.sleep(for: .seconds(max(1, minutes) * 60))
            }
        }
    }

    func refreshNow() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            await self?.refresh()
            self?.refreshTask = nil
        }
    }

    func stop() {
        pump?.cancel()
        pump = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func load() async {
        let secrets = secrets
        let account = account
        let loaded = await Task.detached {
            let preferencesURL = AppPaths.applicationSupport().appending(path: "inbox-preferences.json")
            let cacheURL = AppPaths.caches().appending(path: "inbox.json")
            let preferences = try? JSONDecoder().decode(SavedPreferences.self, from: Data(contentsOf: preferencesURL))
            let snapshot = try? JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: cacheURL))
            let credentials: Result<JiraInboxSource.Credentials?, Error> = Result {
                guard let secret = try secrets.secret(for: account) else { return nil }
                return try JSONDecoder().decode(JiraInboxSource.Credentials.self, from: Data(secret.utf8))
            }
            let executable = await ExecutableLocator.locate("gh")
            return (preferencesURL, cacheURL, preferences, snapshot, credentials, executable)
        }.value
        preferencesURL = loaded.0
        cacheURL = loaded.1
        if let saved = loaded.2 {
            preferences = saved.preferences
            preferences.refreshMinutes = min(60, max(1, preferences.refreshMinutes))
            scope = saved.scope
        }
        switch loaded.4 {
        case .success(let value): setCredentials(value)
        case .failure: credentialError = "Jira credentials could not be read from Keychain. Save the connection again."
        }
        if let snapshot = loaded.3, snapshot.scope == scope {
            items = snapshot.items.filter { $0.source != .jira || jiraConnected }
            refreshedAt = snapshot.fetchedAt
        }
        executable = loaded.5
        isLoading = false
    }

    private func refresh() async {
        guard !isLoading, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let scope = scope
        let organizations = preferences.organizations
        let executable = executable
        let credentials = credentials
        let worker = Task.detached {
            var github: [InboxItem]?
            var jira: [InboxItem]?
            var errors: [String] = []
            do {
                if organizations.isEmpty { github = [] } else if let executable {
                    github = try await GitHubInboxSource.fetch(executable: executable, organizations: organizations)
                } else { throw GitHubInboxSource.SourceError.unavailable }
            } catch { errors.append(error.localizedDescription) }
            guard !Task.isCancelled else { return (github, jira, errors) }
            do {
                if let credentials { jira = try await JiraInboxSource.fetch(credentials) } else { jira = [] }
            } catch { errors.append(error.localizedDescription) }
            return (github, jira, errors)
        }
        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard scope == self.scope, !Task.isCancelled else { return }
        items = (result.0 ?? items.filter { $0.source == .github })
            + (result.1 ?? items.filter { $0.source == .jira })
        errors = result.2 + (credentialError.map { [$0] } ?? [])
        refreshedAt = Date()
        guard let cacheURL else { return }
        let snapshot = Snapshot(scope: scope, items: items, fetchedAt: refreshedAt!)
        do {
            try await Task.detached {
                try JSONEncoder().encode(snapshot).write(to: cacheURL, options: .atomic)
            }.value
        } catch { errors.append("Inbox cache could not be saved.") }
    }

    func save(organizations: String, refreshMinutes: Int) async throws {
        let organizations = try InboxPreferences.organizations(from: organizations)
        let changed = organizations != preferences.organizations
        preferences.organizations = organizations
        preferences.refreshMinutes = min(60, max(1, refreshMinutes))
        if changed {
            scope = UUID()
            items.removeAll { $0.source == .github }
        }
        try await persistPreferences()
        restartRefresh()
    }

    func connectJira(site: String, email: String, token: String) async throws {
        let credentials = try JiraInboxSource.Credentials(site: site, email: email, token: token)
        let secrets = secrets
        let account = account
        try await Task.detached {
            let encoded = try JSONEncoder().encode(credentials)
            guard let secret = String(bytes: encoded, encoding: .utf8) else {
                throw KeychainSecretStore.StoreError.invalidEncoding
            }
            try secrets.setSecret(secret, for: account)
        }.value
        setCredentials(credentials)
        scope = UUID()
        items.removeAll { $0.source == .jira }
        try await persistPreferences()
        restartRefresh()
    }

    func disconnectJira() async throws {
        let secrets = secrets
        let account = account
        try await Task.detached { try secrets.removeSecret(for: account) }.value
        setCredentials(nil)
        scope = UUID()
        items.removeAll { $0.source == .jira }
        try await persistPreferences()
        restartRefresh()
    }

    func markRead(_ item: InboxItem) async throws {
        preferences.readThrough[item.id] = item.updatedAt
        try await persistPreferences()
    }

    func branch(for item: InboxItem) async throws -> String {
        guard let executable else { throw GitHubInboxSource.SourceError.unavailable }
        return try await Task.detached {
            try await GitHubInboxSource.branch(executable: executable, item: item)
        }.value
    }

    private func setCredentials(_ value: JiraInboxSource.Credentials?) {
        credentialError = nil
        credentials = value
        jiraSite = value?.site.absoluteString ?? ""
        jiraEmail = value?.email ?? ""
        jiraConnected = value != nil
    }

    private func restartRefresh() {
        refreshTask?.cancel()
        pump?.cancel()
        pump = Task { [weak self] in
            while !Task.isCancelled {
                if self?.isRefreshing == true {
                    try? await Task.sleep(for: .milliseconds(100))
                    continue
                }
                await self?.refresh()
                let minutes = self?.preferences.refreshMinutes ?? 5
                try? await Task.sleep(for: .seconds(minutes * 60))
            }
        }
    }

    private func persistPreferences() async throws {
        guard let preferencesURL else { throw CocoaError(.fileNoSuchFile) }
        let saved = SavedPreferences(preferences: preferences, scope: scope)
        let previous = saveTask
        let write = Task.detached {
            await previous?.value
            try JSONEncoder().encode(saved).write(to: preferencesURL, options: .atomic)
        }
        saveTask = Task { _ = try? await write.value }
        try await write.value
    }
}
