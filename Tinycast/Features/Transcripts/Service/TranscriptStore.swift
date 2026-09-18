import Foundation
import Observation

@MainActor @Observable
final class TranscriptStore {
    let historyDirectory: URL
    let scribeDirectory: URL
    private(set) var entries: [TranscriptEntry] = []
    private(set) var issue: String?
    @ObservationIgnored private var generation = UUID()

    init(historyDirectory: URL, scribeDirectory: URL) {
        self.historyDirectory = historyDirectory
        self.scribeDirectory = scribeDirectory
    }

    func observe(_ source: TranscriptEntry.Source) async {
        let directory = source == .dictation ? historyDirectory : scribeDirectory
        let calendar = Calendar.current
        let request = UUID()
        generation = request
        entries = []
        issue = nil
        let worker = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
                let watchers = Self.watch(directory: directory, source: source, continuation: continuation)
                let snapshot = Self.read(directory: directory, source: source, calendar: calendar)
                guard !Task.isCancelled else {
                    watchers.forEach { $0.cancel() }
                    continuation.finish()
                    return
                }
                await self?.publish(snapshot, request: request)
                for await _ in stream { break }
                watchers.forEach { $0.cancel() }
                continuation.finish()
                if !Task.isCancelled { try? await Task.sleep(for: .milliseconds(150)) }
            }
        }
        await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard generation == request else { return }
        entries = []
        issue = nil
    }

    private func publish(_ snapshot: Snapshot, request: UUID) {
        guard generation == request else { return }
        entries = snapshot.entries
        issue = snapshot.issue
    }

    nonisolated static func todayURL(directory: URL, now: Date, calendar: Calendar) -> URL {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let name = String(format: "%04d-%02d-%02d.md", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return directory.appendingPathComponent(name)
    }

    private struct Snapshot: Sendable {
        var entries: [TranscriptEntry] = []
        var issue: String?
    }

    nonisolated private static func read(
        directory: URL, source: TranscriptEntry.Source, calendar: Calendar
    ) -> Snapshot {
        var snapshot = Snapshot()
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            var failures = 0
            for file in files {
                guard !Task.isCancelled else { return snapshot }
                do {
                    if source == .dictation {
                        guard file.pathExtension == "md" else { continue }
                        let text = try String(contentsOf: file, encoding: .utf8)
                        snapshot.entries += DictationHistoryParser.parse(text, sourceURL: file, calendar: calendar)
                    } else {
                        guard try file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
                        let document = file.appendingPathComponent("document.json")
                        snapshot.entries.append(try ScribeDocumentDecoder.decode(
                            Data(contentsOf: document), sourceURL: document))
                    }
                } catch { failures += 1 }
            }
            if failures > 0 { snapshot.issue = "Could not read \(failures) transcript files" }
        } catch {
            snapshot.issue = "Transcript directory is missing or unreadable"
        }
        return snapshot
    }

    nonisolated private static func watch(
        directory: URL, source: TranscriptEntry.Source, continuation: AsyncStream<Void>.Continuation
    ) -> [DispatchSourceFileSystemObject] {
        guard source == .dictation else { return [] }
        var ancestor = directory
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            ancestor.deleteLastPathComponent()
        }
        var urls = [ancestor]
        if let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            urls += files.filter { $0.pathExtension == "md" }
        }
        return urls.compactMap { url in
            let descriptor = Darwin.open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { return nil }
            let watcher = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename, .revoke],
                queue: .global(qos: .utility))
            watcher.setEventHandler { continuation.yield(()) }
            watcher.setCancelHandler { Darwin.close(descriptor) }
            watcher.resume()
            return watcher
        }
    }
}
