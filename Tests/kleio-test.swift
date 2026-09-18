import Foundation

@main
@MainActor
struct KleioTests {
    static var failures = 0
    static let documentURL = URL(fileURLWithPath: "/synthetic/library/example/document.json")

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async throws {
        try recordings()
        try queries()
        commandURLs()
        try await library()
        print(failures == 0 ? "Kleio tests passed" : "\(failures) Kleio tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func document(
        id: String = "synthetic-recording", title: String = "Planning notes",
        createdAt: String = "2026-09-18T09:00:00Z", duration: String = "12.5", segments: String = "[]"
    ) -> Data {
        Data("""
        {"id":"\(id)","title":"\(title)","createdAt":"\(createdAt)",
        "duration":\(duration),"segments":\(segments),"kind":"audio","status":"completed"}
        """.utf8)
    }

    static func recording(_ title: String, text: String = "", createdAt: String = "2026-09-18T09:00:00Z",
                          folder: String? = nil) throws -> KleioRecording {
        let url = URL(fileURLWithPath: "/synthetic/library/\(folder ?? title.lowercased())/document.json")
        let segments = text.isEmpty ? "[]" : "[{\"text\":\"\(text)\",\"start\":0,\"end\":1}]"
        return try KleioDocumentDecoder.decode(
            document(title: title, createdAt: createdAt, segments: segments), documentURL: url)
    }

    static func recordings() throws {
        let empty = try KleioDocumentDecoder.decode(document(), documentURL: documentURL)
        expect(empty.text.isEmpty && empty.segments.isEmpty, "an empty recording has no transcript")
        expect(empty.id == documentURL.absoluteString, "the document URL is the identity")
        expect(empty.folderURL.lastPathComponent == "example", "the folder is the document's parent")
        let segments = """
        [{"id":"one","text":"First sentence.","start":0,"end":4.5,"speaker":"Speaker 1"},
         {"id":"two","text":"Second paragraph.\\n\\nStill the second segment.","start":4.5,"end":12.5}]
        """
        let entry = try KleioDocumentDecoder.decode(document(segments: segments), documentURL: documentURL)
        expect(entry.title == "Planning notes" && entry.duration == 12.5, "recording metadata decodes")
        expect(entry.date == Date(timeIntervalSince1970: 1_789_722_000), "createdAt decodes as ISO 8601")
        expect(entry.segments.count == 2 && entry.segments[0].speaker == "Speaker 1",
               "segment timings and speakers decode")
        expect(entry.segments[1].speaker == nil, "a missing speaker is allowed")
        expect(entry.text == "First sentence.\nSecond paragraph.\n\nStill the second segment.",
               "the full transcript retains paragraphs and segment order")
        expect(entry.text(in: 0...0) == "First sentence.", "one segment can be copied")
        expect(entry.text(in: 0...1) == entry.text, "a segment range includes both endpoints")
        expect(entry.text(in: -1...0) == nil && entry.text(in: 1...2) == nil, "out-of-range segments are rejected")
        expect(empty.text(in: 0...0) == nil, "an empty transcript cannot copy a segment")
        let blank = try KleioDocumentDecoder.decode(
            document(segments: "[{\"text\":\"  \",\"start\":0,\"end\":1}]"), documentURL: documentURL)
        expect(blank.text(in: 0...0) == nil, "a blank segment cannot trigger an empty copy")
        let invalid = [
            Data(), Data("{".utf8), Data("{}".utf8), document(id: " "), document(duration: "-1"),
            document(duration: "1e308"), document(createdAt: "yesterday"),
            document(segments: "[{\"text\":\"Invalid\",\"start\":3,\"end\":2}]"),
            document(segments: "[{\"text\":\"Invalid\",\"start\":-1,\"end\":2}]"),
            document(segments: "[{\"text\":\"Invalid\"}]")
        ]
        for data in invalid {
            do {
                _ = try KleioDocumentDecoder.decode(data, documentURL: documentURL)
                expect(false, "malformed documents and invalid ranges must throw")
            } catch {}
        }
    }

    static func queries() throws {
        let entries = [
            try recording("Calendar", createdAt: "2026-09-18T08:00:00Z"),
            try recording("Shopping list", createdAt: "2026-09-18T09:00:00Z", folder: "shopping"),
            try recording("Calendar planning", createdAt: "2026-09-18T10:00:00Z", folder: "planning")
        ]
        expect(KleioQuery.rank(entries, for: " ").map(\.title) ==
               ["Calendar planning", "Shopping list", "Calendar"], "blank queries show newest first")
        expect(KleioQuery.rank(entries, for: "calendar").first?.title == "Calendar", "exact matches rank first")
        expect(KleioQuery.rank(entries, for: "clndr").count == 2, "fuzzy subsequences match")
        expect(KleioQuery.rank(entries, for: "zzzz").isEmpty, "unmatched queries produce no rows")
        let tied = [try recording("Same", folder: "a"), try recording("Same", folder: "b")]
        expect(KleioQuery.rank(tied, for: "Same").map(\.id) ==
               KleioQuery.rank(tied.reversed(), for: "Same").map(\.id), "ties have deterministic order")
        let body = [try recording("Title", text: "Hidden keyword")]
        expect(KleioQuery.rank(body, for: "keyword").count == 1, "search includes the full transcript")
        let large = try (0..<250).map { try recording("Entry \($0)", folder: "entry-\($0)") }
        expect(KleioQuery.rank(large, for: "").count == KleioQuery.resultLimit, "blank results obey the row limit")
        expect(KleioQuery.rank(large, for: "Entry").count == KleioQuery.resultLimit,
               "matching results obey the row limit")
    }

    static func commandURLs() {
        let expected: [(KleioCommandURL, String)] = [
            (.startRecording(.meeting), "kleio://record/start?mode=meeting"),
            (.startRecording(.system), "kleio://record/start?mode=system"),
            (.startRecording(.mic), "kleio://record/start?mode=mic"),
            (.stopRecording, "kleio://record/stop"),
            (.toggleRecording(.meeting), "kleio://record/toggle?mode=meeting"),
            (.toggleDictation, "kleio://dictation/toggle")
        ]
        for (command, string) in expected {
            expect(command.url.absoluteString == string, "\(command) builds \(string), got \(command.url)")
            expect(command.url.scheme == KleioCommandURL.scheme, "\(command) uses the kleio scheme")
            expect(command.successMessage.hasPrefix("Kleio: "), "\(command) names Kleio in its HUD message")
        }
        expect(Set(expected.map(\.0.successMessage)).count == expected.count, "each command has its own message")
    }

    static func library() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-kleio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = KleioStore(libraryDirectory: root.appendingPathComponent("not-created"))
        await missing.load()
        expect(missing.recordings.isEmpty && missing.issue != nil, "a missing library reports an issue")

        let library = root.appendingPathComponent("library")
        for name in ["first", "second"] {
            let folder = library.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try document(id: name, title: "Synthetic \(name)", createdAt: "2026-09-18T0\(name.count):00:00Z")
                .write(to: folder.appendingPathComponent("document.json"))
        }
        try Data("not a recording".utf8).write(to: library.appendingPathComponent("stray.txt"))
        try FileManager.default.createDirectory(
            at: library.appendingPathComponent(".hidden"), withIntermediateDirectories: true)
        let store = KleioStore(libraryDirectory: library)
        await store.load()
        expect(store.recordings.count == 2 && store.issue == nil, "each recording folder yields one row")
        expect(Set(store.recordings.map(\.title)) == ["Synthetic first", "Synthetic second"],
               "titles come from document.json")
        expect(store.recordings.allSatisfy { $0.documentURL.lastPathComponent == "document.json" },
               "rows point at their document")

        let malformed = library.appendingPathComponent("malformed")
        try FileManager.default.createDirectory(at: malformed, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: malformed.appendingPathComponent("document.json"))
        try FileManager.default.createDirectory(
            at: library.appendingPathComponent("empty-folder"), withIntermediateDirectories: true)
        await store.load()
        expect(store.recordings.count == 2, "valid recordings survive a malformed neighbour")
        expect(store.issue == "Could not read 2 Kleio recordings", "the issue counts every unreadable folder")

        store.release()
        expect(store.recordings.isEmpty && store.issue == nil, "release clears rows and the issue")
        let cancelled = Task { await store.load() }
        cancelled.cancel()
        await cancelled.value
        expect(store.recordings.isEmpty, "a cancelled load publishes nothing")
        let stale = Task { await store.load() }
        await Task.yield()
        store.release()
        await stale.value
        expect(store.recordings.isEmpty, "a load superseded by release publishes nothing")
        await store.load()
        expect(store.recordings.count == 2, "a fresh load after release reads again")
    }
}
