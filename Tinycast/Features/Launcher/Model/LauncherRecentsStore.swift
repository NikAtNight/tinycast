import Foundation

/// What was launched lately, newest first, for the opening list's Recent section.
/// Separate from `LauncherRankingStore`: a launch with nothing typed teaches no query, but it is
/// still the thing the user reached for last, and only a labelled section may show that.
@MainActor
@Observable
final class LauncherRecentsStore {
    /// Kept on disk; the section shows `sectionLimit` of them so a hidden or removed item can fall out.
    private static let cap = 30
    nonisolated static let sectionLimit = 5

    private let fileURL: URL

    /// Preference keys, newest first, never repeated.
    private(set) var keys: [String]
    /// Part of `AppIndex`'s cache key, invalidating the opening list after a launch or a clear.
    private(set) var revision = 0

    @ObservationIgnored private var writeTask: Task<Void, Never>?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        if let data = try? Data(contentsOf: self.fileURL),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        {
            keys = Array(decoded.filter { !$0.isEmpty }.prefix(Self.cap))
        } else {
            keys = []
        }
    }

    var isEmpty: Bool { keys.isEmpty }

    /// Awaits the pending persist. The launcher never needs it; reading the file back does.
    func flush() async {
        await writeTask?.value
    }

    func record(itemKey: String) {
        guard !itemKey.isEmpty else { return }
        keys.removeAll { $0 == itemKey }
        keys.insert(itemKey, at: 0)
        if keys.count > Self.cap { keys.removeLast(keys.count - Self.cap) }
        didMutate()
    }

    func remove(itemKey: String) {
        let before = keys.count
        keys.removeAll { $0 == itemKey }
        if keys.count != before { didMutate() }
    }

    func clear() {
        guard !keys.isEmpty else { return }
        keys = []
        didMutate()
    }

    private func didMutate() {
        revision &+= 1
        let snapshot = keys
        let fileURL = fileURL
        let previous = writeTask
        writeTask = Task.detached(priority: .utility) {
            await previous?.value
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Application Support, beside the ranking: a list of what was reached for is not refetchable.
    private static func defaultFileURL() -> URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.tinycast.app"
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("launcher-recents.json")
    }
}
