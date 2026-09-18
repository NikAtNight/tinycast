import Foundation

final class ClipShareClient: Sendable {
    private let baseURL: URL
    private let token: String
    private let session: URLSession

    init(baseURL: URL, token: String) throws {
        let local = ["localhost", "127.0.0.1", "::1"].contains(baseURL.host ?? "")
        guard baseURL.host != nil, baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil,
              baseURL.scheme == "https" || (baseURL.scheme == "http" && local),
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw ClipShareError.invalidConfiguration }
        self.baseURL = baseURL
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 60
        session = URLSession(configuration: configuration)
    }

    deinit { session.invalidateAndCancel() }

    func create(_ metadata: ClipShareCreateRequest) async throws -> ClipShareCreateResponse {
        var request = request(path: "api/videos", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(metadata)
        for attempt in 0..<3 {
            do { return try await send(request) } catch {
                try Task.checkCancellation()
                guard attempt < 2, Self.isRetryable(error) else { throw error }
                try await Task.sleep(for: .seconds(attempt + 1))
            }
        }
        throw ClipShareError.invalidResponse
    }

    func status(id: String) async throws -> ClipShareStatusResponse {
        try await send(request(path: "api/videos/\(id)", method: "GET"))
    }

    func complete(id: String) async throws -> ClipShareCompleteResponse {
        try await send(request(path: "api/videos/\(id)/complete", method: "POST"))
    }

    func recent() async throws -> [ClipShareVideo] {
        var request = request(path: "api/videos", method: "GET")
        request.url?.append(queryItems: [URLQueryItem(name: "limit", value: "20")])
        let result: ClipShareListResponse = try await send(request)
        return result.videos
    }

    func revoke(id: String) async throws -> ClipShareCompleteResponse {
        try await send(request(path: "api/videos/\(id)/revoke", method: "POST"))
    }

    func delete(id: String) async throws {
        _ = try await response(request(path: "api/videos/\(id)", method: "DELETE"))
    }

    func upload(
        fileURL: URL, metadata: ClipShareCreateRequest, resumeID: String? = nil,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> ClipShareCompleteResponse {
        let actualSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard actualSize.map(Int64.init) == metadata.sizeBytes else { throw ClipShareError.fileChanged }
        let id: String
        if let resumeID { id = resumeID } else { id = try await create(metadata).video.id }
        for attempt in 0..<3 {
            do {
                return try await resume(fileURL: fileURL, size: metadata.sizeBytes, id: id, progress: progress)
            } catch {
                try Task.checkCancellation()
                guard attempt < 2, Self.isRetryable(error) else { throw error }
                try await Task.sleep(for: .seconds(attempt + 1))
            }
        }
        throw ClipShareError.invalidResponse
    }

    private func resume(
        fileURL: URL, size: Int64, id: String,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> ClipShareCompleteResponse {
        let state = try await status(id: id)
        guard state.video.sizeBytes == size else { throw ClipShareError.invalidUpload }
        if state.video.status == .ready {
            await progress(1)
            return try await complete(id: id)
        }
        guard state.video.status == .uploading else { throw ClipShareError.invalidUpload }
        let plan = try ClipShareUploadPlan(sizeBytes: size, partSizeBytes: state.partSizeBytes)
        guard plan.parts.count == state.partCount,
              state.uploadedParts.allSatisfy({ (1...plan.parts.count).contains($0) })
        else { throw ClipShareError.invalidResponse }
        let uploaded = Set(state.uploadedParts)
        var sent = plan.parts.filter { uploaded.contains($0.number) }.reduce(Int64(0)) { $0 + $1.length }
        await progress(Double(sent) / Double(size))
        for part in plan.parts where !uploaded.contains(part.number) {
            try Task.checkCancellation()
            try await uploadPart(part, fileURL: fileURL, id: id)
            sent += part.length
            await progress(Double(sent) / Double(size))
        }
        return try await complete(id: id)
    }

    private func uploadPart(_ part: ClipShareUploadPlan.Part, fileURL: URL, id: String) async throws {
        let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let source = try FileHandle(forReadingFrom: fileURL)
        defer { try? source.close() }
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let destination = try FileHandle(forWritingTo: temporary)
        defer { try? destination.close() }
        try source.seek(toOffset: UInt64(part.offset))
        var remaining = part.length
        while remaining > 0 {
            try Task.checkCancellation()
            let data = try source.read(upToCount: Int(min(1_048_576, remaining))) ?? Data()
            guard !data.isEmpty else { throw ClipShareError.fileChanged }
            try destination.write(contentsOf: data)
            remaining -= Int64(data.count)
        }
        try destination.synchronize()
        var request = request(path: "api/videos/\(id)/parts/\(part.number)", method: "PUT")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(String(part.length), forHTTPHeaderField: "Content-Length")
        let (data, response) = try await session.upload(for: request, fromFile: temporary)
        try Self.validate(response)
        struct Receipt: Decodable { let partNumber: Int; let sizeBytes: Int64; let etag: String }
        let receipt = try JSONDecoder().decode(Receipt.self, from: data)
        guard receipt.partNumber == part.number, receipt.sizeBytes == part.length else {
            throw ClipShareError.invalidResponse
        }
    }

    private func request(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func response(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return data
    }

    private func send<Value: Decodable>(_ request: URLRequest) async throws -> Value {
        try Self.decoder().decode(Value.self, from: await response(request))
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            let strategy = Date.ISO8601FormatStyle().year().month().day()
                .time(includingFractionalSeconds: true).timeZone(separator: .omitted)
            guard let date = try? Date(text, strategy: strategy) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date")
            }
            return date
        }
        return decoder
    }

    private static func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw ClipShareError.invalidResponse }
        guard (200...299).contains(response.statusCode) else { throw ClipShareError.server(response.statusCode) }
    }

    private static func isRetryable(_ error: Error) -> Bool {
        if case ClipShareError.server(let status) = error {
            return status == 408 || status == 429 || status >= 500
        }
        return (error as? URLError).map { $0.code != .cancelled } ?? false
    }
}
