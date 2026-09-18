import Foundation

@main
@MainActor
struct TranscriptsStoreTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    @discardableResult
    static func waitFor(_ message: String, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        let passed = condition()
        expect(passed, message)
        return passed
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-transcripts-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await liveHistory(root: root)
        try await missingDirectory(root: root)
        try await sourceSwitching(root: root)
        try FileManager.default.removeItem(at: root)
        print(failures == 0 ? "Transcript store tests passed" : "\(failures) transcript store tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    static func liveHistory(root: URL) async throws {
        let history = root.appendingPathComponent("live-history")
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        let file = history.appendingPathComponent("2026-09-18.md")
        try write("# Dictations 2026-09-18\n## 09:00:00\nOriginal synthetic text.\n", to: file)
        let store = TranscriptStore(historyDirectory: history, scribeDirectory: root.appendingPathComponent("unused"))
        let observer = Task { await store.observe(.dictation) }
        defer { observer.cancel() }
        await waitFor("initial history read") { store.entries.count == 1 }
        try append("## 10:00:00\nAppended synthetic text.\n", to: file)
        await waitFor("in-place appends refresh the list") { store.entries.count == 2 }
        try write("# Dictations 2026-09-18\n## 11:00:00\nAtomic replacement.\n", to: file)
        await waitFor("atomic replacement refreshes the list") {
            store.entries.count == 1 && store.entries.first?.text == "Atomic replacement."
        }
        try append("## 12:00:00\nAfter replacement.\n", to: file)
        await waitFor("the watcher follows the replacement inode") { store.entries.count == 2 }
        let tomorrow = history.appendingPathComponent("2026-09-19.md")
        try write("# Dictations 2026-09-19\n## 08:00:00\nNew day.\n", to: tomorrow)
        await waitFor("new daily files appear") { store.entries.count == 3 }
        let many = "# Dictations 2026-09-19\n" + (0..<250).map {
            "## 09:00:00\nSynthetic item \($0).\n"
        }.joined()
        try write(many, to: tomorrow)
        await waitFor("the store retains entries beyond the visible row cap") { store.entries.count == 252 }
        expect(TranscriptQuery.rank(store.entries, for: "").count == TranscriptQuery.resultLimit,
               "the displayed list stays capped")
        expect(TranscriptQuery.rank(store.entries, for: "Atomic replacement").first?.text == "Atomic replacement.",
               "a search can find history older than the visible row cap")
        observer.cancel()
        await observer.value
        expect(store.entries.isEmpty && store.issue == nil, "cancellation releases history and issue state")
        try append("## 13:00:00\nAfter cancellation.\n", to: file)
        try await Task.sleep(for: .milliseconds(250))
        expect(store.entries.isEmpty, "cancelled observers cannot publish later writes")
    }

    static func missingDirectory(root: URL) async throws {
        let parent = root.appendingPathComponent("not-created-yet")
        let history = parent.appendingPathComponent("History")
        let store = TranscriptStore(historyDirectory: history, scribeDirectory: root.appendingPathComponent("unused"))
        let observer = Task { await store.observe(.dictation) }
        defer { observer.cancel() }
        await waitFor("missing directory reports an issue") { store.issue != nil }
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        let file = history.appendingPathComponent("2026-09-18.md")
        try write("# Dictations 2026-09-18\n## 09:00:00\nRecovered history.\n", to: file)
        await waitFor("an ancestor watcher discovers a newly created history directory") {
            store.entries.first?.text == "Recovered history." && store.issue == nil
        }
        observer.cancel()
        await observer.value
        expect(store.entries.isEmpty, "recovered history clears on cancellation")
    }

    static func sourceSwitching(root: URL) async throws {
        let history = root.appendingPathComponent("switch-history")
        let library = root.appendingPathComponent("library")
        let recording = library.appendingPathComponent("synthetic-recording")
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recording, withIntermediateDirectories: true)
        let file = history.appendingPathComponent("2026-09-18.md")
        try write("# Dictations 2026-09-18\n## 09:00:00\nBefore switching.\n", to: file)
        try write("""
        {"id":"synthetic-recording","title":"Synthetic meeting","createdAt":"2026-09-18T09:00:00Z",
         "duration":1,"segments":[{"text":"Synthetic transcript.","start":0,"end":1}]}
        """, to: recording.appendingPathComponent("document.json"))
        let malformed = library.appendingPathComponent("malformed-recording")
        try FileManager.default.createDirectory(at: malformed, withIntermediateDirectories: true)
        try write("{", to: malformed.appendingPathComponent("document.json"))
        let store = TranscriptStore(historyDirectory: history, scribeDirectory: library)
        let historyObserver = Task { await store.observe(.dictation) }
        defer { historyObserver.cancel() }
        await waitFor("history loads before switching") { store.entries.first?.source == .dictation }
        let recordingObserver = Task { await store.observe(.scribe) }
        defer { recordingObserver.cancel() }
        await waitFor("Scribe replaces the history source") {
            store.entries.count == 1 && store.entries.first?.source == .scribe
        }
        expect(store.issue != nil, "a malformed recording is reported while valid recordings remain")
        try append("## 10:00:00\nStale history event.\n", to: file)
        try await Task.sleep(for: .milliseconds(350))
        expect(store.entries.count == 1 && store.entries.first?.source == .scribe,
               "a superseded source cannot publish after a source switch")
        historyObserver.cancel()
        await historyObserver.value
        expect(store.entries.first?.source == .scribe, "old cancellation cannot erase the new source")
        recordingObserver.cancel()
        await recordingObserver.value
        expect(store.entries.isEmpty && store.issue == nil, "Scribe cancellation releases entries and issues")
    }
}
