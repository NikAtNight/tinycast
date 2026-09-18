import Foundation

/// The two Web API requests and the query rule, built here so a harness can pin their shape.
enum SpotifyAPI {
    static let tokenEndpoint = URL(string: "https://accounts.spotify.com/api/token")!
    static let searchEndpoint = URL(string: "https://api.spotify.com/v1/search")!
    /// Per type, so four sections of eight fit the palette without a scroll on most queries.
    static let resultLimit = 8
    static let debounce: Duration = .milliseconds(250)
    static let timeout: TimeInterval = 15

    /// The client-credentials grant: HTTP basic auth of id and secret, no user login involved.
    static func tokenRequest(clientID: String, clientSecret: String) -> URLRequest {
        var request = URLRequest(url: tokenEndpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = Data("grant_type=client_credentials".utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let credentials = Data("\(clientID):\(clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func searchRequest(query: String, token: String) -> URLRequest {
        var components = URLComponents(url: searchEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(
                name: "type", value: SpotifyItem.Kind.allCases.map(\.rawValue).joined(separator: ",")),
            URLQueryItem(name: "limit", value: String(resultLimit))
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: timeout)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Nil for a query that would search nothing; whitespace alone is never sent.
    static func normalizedQuery(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// A bearer token held in memory only, refreshed before it can expire mid-request.
struct SpotifyAccessToken: Equatable, Sendable {
    static let refreshMargin: TimeInterval = 60

    let value: String
    let expiresAt: Date

    init(value: String, expiresAt: Date) {
        self.value = value
        self.expiresAt = expiresAt
    }

    init(response: SpotifyTokenResponse, now: Date) {
        self.init(value: response.accessToken, expiresAt: now.addingTimeInterval(response.expiresIn))
    }

    func isUsable(at now: Date) -> Bool {
        expiresAt.timeIntervalSince(now) > Self.refreshMargin
    }
}

/// What the screen shows inline; nothing here ever becomes a dialog.
enum SpotifySearchError: Error, Equatable, Sendable {
    case missingCredentials
    case unauthorized
    case rateLimited
    case offline
    case http(Int)
    case malformed

    /// The token endpoint answers a bad secret with 400, so it reads as unauthorized too.
    init(status: Int) {
        switch status {
        case 400, 401, 403: self = .unauthorized
        case 429: self = .rateLimited
        default: self = .http(status)
        }
    }

    var message: String {
        switch self {
        case .missingCredentials: return "Add a Spotify Client ID and Client Secret in Settings."
        case .unauthorized: return "Spotify rejected the credentials. Check them in Spotify Settings."
        case .rateLimited: return "Spotify is rate limiting requests. Try again in a moment."
        case .offline: return "Spotify is unreachable. Check your connection."
        case .http(let status): return "Spotify answered with HTTP \(status)."
        case .malformed: return "Spotify sent a response Tinycast could not read."
        }
    }
}

/// The AppleScript that plays a URI in the desktop app; one form serves every kind.
enum SpotifyPlayScript {
    /// Nil for anything but a plain Spotify URI, so no text can reach the script unquoted.
    static func source(uri: String) -> String? {
        guard uri.wholeMatch(of: /spotify:(track|artist|album|playlist):[A-Za-z0-9]+/) != nil else {
            return nil
        }
        return "tell application \"Spotify\" to play track \"\(uri)\""
    }
}
