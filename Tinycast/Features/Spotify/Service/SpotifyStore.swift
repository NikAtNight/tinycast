import Foundation

/// Credentials in Keychain, a token in memory, and the cacheless session every request rides.
@MainActor
@Observable
final class SpotifyStore {
    nonisolated static let clientIDSecrets = KeychainSecretStore(scope: "spotify.clientID")
    nonisolated static let clientSecretSecrets = KeychainSecretStore(scope: "spotify.clientSecret")
    nonisolated static let account = UUID(uuidString: "A04622E3-F668-465E-BC1A-6B6AFD9A9C23")!

    /// Both halves present, read off main; the screen's empty state keys on it.
    private(set) var hasCredentials = false
    @ObservationIgnored private var token: SpotifyAccessToken?
    @ObservationIgnored private var presence: Task<Void, Never>?

    func start() {
        presence?.cancel()
        presence = Task { [weak self] in await self?.refreshCredentialPresence() }
    }

    func refreshCredentialPresence() async {
        let present = await Task.detached {
            (try? Self.clientIDSecrets.hasSecret(for: Self.account)) == true
                && (try? Self.clientSecretSecrets.hasSecret(for: Self.account)) == true
        }.value
        hasCredentials = present
    }

    /// The pane prefills the id; the secret is never read back into a field.
    func clientID() async -> String? {
        await Task.detached { try? Self.clientIDSecrets.secret(for: Self.account) }.value
    }

    /// An empty secret keeps the saved one, so retyping the id never demands the secret again.
    func saveCredentials(clientID: String, clientSecret: String) async throws {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw SpotifySearchError.missingCredentials }
        try await Task.detached {
            if secret.isEmpty {
                guard try Self.clientSecretSecrets.hasSecret(for: Self.account) else {
                    throw SpotifySearchError.missingCredentials
                }
            } else {
                try Self.clientSecretSecrets.setSecret(secret, for: Self.account)
            }
            try Self.clientIDSecrets.setSecret(id, for: Self.account)
        }.value
        token = nil
        hasCredentials = true
    }

    func removeCredentials() async throws {
        try await Task.detached {
            try Self.clientIDSecrets.removeSecret(for: Self.account)
            try Self.clientSecretSecrets.removeSecret(for: Self.account)
        }.value
        token = nil
        hasCredentials = false
    }

    func search(_ query: String) async throws -> SpotifySearchResults {
        let token = try await accessToken()
        do {
            return try await Self.performSearch(query: query, token: token)
        } catch SpotifySearchError.unauthorized {
            // Dropped so the next search fetches afresh, in case the token outlived its grant.
            self.token = nil
            throw SpotifySearchError.unauthorized
        }
    }

    /// Settings' Test Connection: a fresh token, whatever is cached.
    func testConnection() async throws {
        token = try await Self.fetchToken(credentials: try await credentials())
    }

    private func accessToken() async throws -> String {
        if let token, token.isUsable(at: Date()) { return token.value }
        let fresh = try await Self.fetchToken(credentials: try await credentials())
        token = fresh
        return fresh.value
    }

    private func credentials() async throws -> (id: String, secret: String) {
        let read = await Task.detached { () -> (String, String)? in
            guard let id = try? Self.clientIDSecrets.secret(for: Self.account),
                let secret = try? Self.clientSecretSecrets.secret(for: Self.account),
                !id.isEmpty, !secret.isEmpty
            else { return nil }
            return (id, secret)
        }.value
        guard let read else {
            hasCredentials = false
            throw SpotifySearchError.missingCredentials
        }
        return read
    }

    /// Cacheless, never `URLSession.shared`: artwork on disk stays the only copy Tinycast keeps.
    nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }()

    private nonisolated static func fetchToken(
        credentials: (id: String, secret: String)
    ) async throws -> SpotifyAccessToken {
        let request = SpotifyAPI.tokenRequest(clientID: credentials.id, clientSecret: credentials.secret)
        let (data, status) = try await perform(request)
        guard status == 200 else { throw SpotifySearchError(status: status) }
        guard let response = try? SpotifyTokenResponse.decode(data) else {
            throw SpotifySearchError.malformed
        }
        return SpotifyAccessToken(response: response, now: Date())
    }

    private nonisolated static func performSearch(
        query: String, token: String
    ) async throws -> SpotifySearchResults {
        let (data, status) = try await perform(SpotifyAPI.searchRequest(query: query, token: token))
        guard status == 200 else { throw SpotifySearchError(status: status) }
        guard let response = try? SpotifySearchResponse.decode(data) else {
            throw SpotifySearchError.malformed
        }
        return SpotifySearchResults(response: response)
    }

    private nonisolated static func perform(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SpotifySearchError.malformed }
            return (data, http.statusCode)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is URLError {
            throw SpotifySearchError.offline
        }
    }
}
