import Foundation
import Observation

@MainActor @Observable
final class KleioStore {
    let libraryDirectory: URL
    private(set) var recordings: [KleioRecording] = []
    private(set) var issue: String?
    @ObservationIgnored private var generation = UUID()

    init(libraryDirectory: URL) {
        self.libraryDirectory = libraryDirectory
    }

    /// Reads the library once. A cancelled load, or one superseded by `release`, publishes nothing.
    func load() async {
        let request = UUID()
        generation = request
        let directory = libraryDirectory
        let reader = Task.detached(priority: .utility) { Self.read(directory: directory) }
        let snapshot = await withTaskCancellationHandler {
            await reader.value
        } onCancel: {
            reader.cancel()
        }
        guard generation == request, !Task.isCancelled else { return }
        recordings = snapshot.recordings
        issue = snapshot.issue
    }

    func release() {
        generation = UUID()
        recordings = []
        issue = nil
    }

    private struct Snapshot: Sendable {
        var recordings: [KleioRecording] = []
        var issue: String?
    }

    nonisolated private static func read(directory: URL) -> Snapshot {
        var snapshot = Snapshot()
        do {
            let folders = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            var failures = 0
            for folder in folders {
                guard !Task.isCancelled else { return snapshot }
                do {
                    guard try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
                    let document = folder.appendingPathComponent("document.json")
                    snapshot.recordings.append(try KleioDocumentDecoder.decode(
                        Data(contentsOf: document), documentURL: document))
                } catch { failures += 1 }
            }
            if failures > 0 { snapshot.issue = "Could not read \(failures) Kleio recordings" }
        } catch {
            snapshot.issue = "Kleio library is missing or unreadable"
        }
        return snapshot
    }
}
