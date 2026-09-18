import Foundation

enum JiraInboxSource {
    struct Credentials: Codable, Sendable {
        let site: URL
        let email: String
        let token: String

        init(site: String, email: String, token: String) throws {
            guard let url = URL(string: site.trimmingCharacters(in: .whitespacesAndNewlines)),
                url.scheme == "https", let host = url.host, host.hasSuffix(".atlassian.net"),
                url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                url.path.isEmpty || url.path == "/",
                !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !token.isEmpty
            else { throw SourceError.invalidConfiguration }
            self.site = url
            self.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
            self.token = token
        }
    }

    enum SourceError: LocalizedError {
        case invalidConfiguration, failed(Int), invalidPage
        var errorDescription: String? {
            switch self {
            case .invalidConfiguration: "Enter an HTTPS Jira Cloud site, email, and API token."
            case .failed(let status): "Jira returned HTTP \(status). Check the connection in Inbox settings."
            case .invalidPage: "Jira returned an invalid search page."
            }
        }
    }

    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    nonisolated static func fetch(_ credentials: Credentials) async throws -> [InboxItem] {
        var items: [InboxItem] = []
        var token: String?
        var seen: Set<String> = []
        repeat {
            var components = URLComponents(url: credentials.site.appending(path: "rest/api/3/search/jql"),
                                           resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "jql", value: "assignee=currentUser() AND resolution=Unresolved ORDER BY updated DESC"),
                URLQueryItem(name: "fields", value: "summary,status,updated,project"),
                URLQueryItem(name: "maxResults", value: "100")
            ]
            if let token { components.queryItems?.append(URLQueryItem(name: "nextPageToken", value: token)) }
            var request = URLRequest(url: components.url!, timeoutInterval: 15)
            let authorization = Data("\(credentials.email):\(credentials.token)".utf8).base64EncodedString()
            request.setValue("Basic \(authorization)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw SourceError.failed((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            let page = try JiraSearchDecoder.decode(data, site: credentials.site)
            items += page.items
            token = page.nextPageToken
            if let token, !seen.insert(token).inserted { throw SourceError.invalidPage }
            try Task.checkCancellation()
        } while token != nil
        return items
    }
}
