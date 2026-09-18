import Foundation

@MainActor
final class TalixClient {
    enum ClientError: String, LocalizedError {
        case missingKey = "Add your Talix API key in Settings first."
        case credentials = "Talix rejected the API key. Check the selected environment and key in Settings."
        case connection = "Could not reach Talix. Your timer and draft are still saved."
        case sessionEnded = "Talix ended the session. Retry to open a new session."
        case http = "Talix could not complete the request. Try again later."
        var errorDescription: String? { rawValue }
    }

    nonisolated static let secrets = KeychainSecretStore(scope: "talix.apiKey")
    nonisolated static let account = UUID(uuidString: "BA4E1352-495B-42C6-BA0A-09A1BFDF43E8")!

    private let endpoint: URL
    private let key: @Sendable () throws -> String?
    private var sessionID: String?
    private var nextID = 1

    init(endpoint: URL, key: @escaping @Sendable () throws -> String?) {
        self.endpoint = endpoint
        self.key = key
    }

    convenience init(environment: TalixEnvironment) {
        self.init(endpoint: environment.endpoint, key: {
            try KeychainSecretStore(scope: "talix.apiKey").secret(
                for: UUID(uuidString: "BA4E1352-495B-42C6-BA0A-09A1BFDF43E8")!)
        })
    }

    func projects() async throws -> [TalixProject] {
        let id = takeID()
        return try await decode(TalixRPC.Projects.self, body: TalixRPC.projects(id: id), id: id).projects
    }

    func entries(projectId: String, day: String) async throws -> [TalixTimeEntry] {
        var entries: [TalixTimeEntry] = []
        while true {
            let id = takeID()
            let page = try await decode(TalixRPC.Entries.self, body: TalixRPC.entries(
                id: id, projectId: projectId, startDate: day, endDate: day, offset: entries.count), id: id)
            guard page.projectId == projectId, page.total >= entries.count else { throw TalixRPC.RPCError.malformed }
            entries += page.items
            if entries.count >= page.total { return entries }
            guard !page.items.isEmpty else { throw TalixRPC.RPCError.malformed }
        }
    }

    func create(projectId: String, entry: TalixTimeEntry) async throws -> TalixTimeEntry {
        let id = takeID()
        return try await decode(TalixRPC.Created.self, body: TalixRPC.create(
            id: id, projectId: projectId, entry: entry), id: id).item
    }

    private func takeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    private func decode<T: Decodable & Sendable>(_ type: T.Type, body: Data, id: Int) async throws -> T {
        let key = try await Task.detached { [key] in try key() }.value
        guard let key, !key.isEmpty else { throw ClientError.missingKey }
        let endpoint = endpoint
        let sessionID = sessionID
        let result = try await Task.detached {
            try await Self.post(endpoint: endpoint, key: key, sessionID: sessionID, body: body, id: id)
        }.value
        if result.status == 404, sessionID != nil {
            self.sessionID = nil
            throw ClientError.sessionEnded
        }
        guard result.status != 401, result.status != 403 else { throw ClientError.credentials }
        guard (200...299).contains(result.status) else { throw ClientError.http }
        if let session = result.session { self.sessionID = session }
        let payload = try TalixRPC.payload(result.data, id: id)
        return try JSONDecoder().decode(type, from: payload)
    }

    private nonisolated static func post(
        endpoint: URL, key: String, sessionID: String?, body: Data, id: Int
    ) async throws -> (data: Data, status: Int, session: String?) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(MCPProtocol.version, forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ClientError.http }
            var result = data
            if http.mimeType == "text/event-stream" {
                var parser = SSEParser()
                let frames = parser.feed(data) + parser.finish()
                guard let frame = frames.last(where: {
                    (try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])?["id"] as? Int == id
                }) else { throw TalixRPC.RPCError.malformed }
                result = Data(frame.utf8)
            }
            return (result, http.statusCode, http.value(forHTTPHeaderField: "Mcp-Session-Id"))
        } catch is URLError {
            throw ClientError.connection
        }
    }
}
