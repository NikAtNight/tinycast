import Foundation

@main
struct ClipShareTests {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }

    static func metadata(_ name: String) -> ClipShareCreateRequest {
        ClipShareCreateRequest(idempotencyKey: UUID().uuidString, originalFilename: name,
                               sizeBytes: 10, durationSeconds: 1, width: 16, height: 16)
    }

    static func main() async throws {
        let plan = try ClipShareUploadPlan(sizeBytes: 10, partSizeBytes: 4)
        require(plan.parts == [.init(number: 1, offset: 0, length: 4),
                               .init(number: 2, offset: 4, length: 4),
                               .init(number: 3, offset: 8, length: 2)], "part ranges")
        require(try ClipShareUploadPlan(sizeBytes: 8, partSizeBytes: 4).parts.count == 2, "exact boundary")
        require(try ClipShareUploadPlan(sizeBytes: 1, partSizeBytes: .max).parts.first?.length == 1, "large part size")
        for (size, partSize): (Int64, Int64) in [(0, 4), (-1, 4), (1, 0), (.max, 4)] {
            do {
                _ = try ClipShareUploadPlan(sizeBytes: size, partSizeBytes: partSize)
                fatalError("invalid plan accepted")
            } catch ClipShareError.invalidUpload { }
        }
        let older = URL(filePath: "/recordings/old.mov")
        let newest = URL(filePath: "/recordings/new.MP4")
        let listing: [ClipShareUploadPlan.Recording] = [
            .init(url: older, modifiedAt: Date(timeIntervalSince1970: 1), isRegularFile: true),
            .init(url: newest, modifiedAt: Date(timeIntervalSince1970: 2), isRegularFile: true),
            .init(url: URL(filePath: "/recordings/image.png"), modifiedAt: .distantFuture, isRegularFile: true),
            .init(url: URL(filePath: "/recordings/folder.mov"), modifiedAt: .distantFuture, isRegularFile: false)
        ]
        require(ClipShareUploadPlan.newestRecording(in: listing) == newest, "newest video only")
        require(ClipShareUploadPlan.newestRecording(in: []) == nil, "empty listing")
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appending(path: "image.png")
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jPioAAAAASUVORK5CYII="
        try Data(base64Encoded: png)!.write(to: image)
        do {
            _ = try await ClipShareMediaExporter.prepare(image, temporaryDirectory: directory, progress: { _ in })
            fatalError("PNG accepted as video")
        } catch { }
        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        require(remaining == ["image.png"], "failed export leaves no temporary file")
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ClipShareMediaExporter.prepare(image, temporaryDirectory: directory, progress: { _ in })
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("cancelled export completed") } catch is CancellationError { }
        let portFile = directory.appending(path: "port")
        let server = Process()
        server.executableURL = URL(filePath: "/usr/bin/env")
        server.arguments = ["node", "Tests/clipshare-fixtures/server.js", portFile.path]
        try server.run()
        defer { server.terminate(); server.waitUntilExit() }
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: portFile.path) {
            try await Task.sleep(for: .milliseconds(50))
        }
        let port = try String(contentsOf: portFile, encoding: .utf8)
        let baseURL = URL(string: "http://127.0.0.1:\(port)")!
        let client = try ClipShareClient(baseURL: baseURL, token: "fixture-token")
        let file = directory.appending(path: "video.mp4")
        try Data("abcdefghij".utf8).write(to: file)
        for filename in ["normal.mp4", "resume.mp4", "lost-create.mp4"] {
            let completed = try await client.upload(fileURL: file, metadata: metadata(filename), progress: { _ in })
            require(completed.video.status == .ready, "upload completed")
            require(completed.video.readyAt != nil, "fractional ISO8601 decoded")
            let status = try await client.status(id: completed.video.id)
            require(status.uploadedParts.sorted() == [1, 2, 3], "all parts uploaded")
            let revoked = try await client.revoke(id: completed.video.id)
            require(revoked.shareUrl != completed.shareUrl, "revoke rotates link")
            try await client.delete(id: completed.video.id)
        }
        require(try await client.recent().isEmpty, "delete removes records")
        let pending = try await client.create(metadata("explicit-resume.mp4"))
        let resumed = try await client.upload(fileURL: file, metadata: metadata("explicit-resume.mp4"),
                                             resumeID: pending.video.id, progress: { _ in })
        require(resumed.video.id == pending.video.id, "explicit resume preserves id")
        let unauthorized = try ClipShareClient(baseURL: baseURL, token: "wrong")
        do { _ = try await unauthorized.recent(); fatalError("unauthorized accepted") } catch ClipShareError.server(401) { }
        do {
            _ = try await client.status(id: "missing")
            fatalError("missing video accepted")
        } catch ClipShareError.server(404) { }
        do {
            _ = try ClipShareClient(baseURL: URL(string: "http://example.com")!, token: "fixture")
            fatalError("insecure remote accepted")
        } catch ClipShareError.invalidConfiguration { }
        print("ClipShare plan, selection, decoding, multipart, retry, resume and actions passed")
    }
}
