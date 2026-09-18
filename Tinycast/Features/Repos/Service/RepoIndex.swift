import Foundation

@MainActor
@Observable
final class RepoIndex {
    private(set) var repositories: [Repository] = []
    private(set) var isScanning = false
    private(set) var error: String?
    @ObservationIgnored private var roots: [String] = []
    @ObservationIgnored private var ignores: [String] = []
    @ObservationIgnored private var scannedAt: Date?
    @ObservationIgnored private var revision = 0
    private(set) var showRevision = 0
    @ObservationIgnored private var statusPaths: Set<String> = []
    @ObservationIgnored private var activeStatuses = 0
    @ObservationIgnored private var gitLookup: Task<URL?, Never>?
    @ObservationIgnored private var scanTask: Task<Snapshot, Never>?

    private struct Snapshot: Codable, Sendable {
        let roots: [String]
        let ignores: [String]
        let date: Date
        let repositories: [Repository]
        var warning: String?
    }

    func configure(roots: [String], ignores: [String]) {
        guard self.roots != roots || self.ignores != ignores else { return }
        self.roots = roots
        self.ignores = ignores
        revision += 1
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        scannedAt = nil
        repositories = []
        endShow()
    }

    func beginShow() async {
        endShow()
        for index in repositories.indices { repositories[index].isDirty = nil }
        await refresh()
    }

    func endShow() {
        showRevision += 1
        statusPaths.removeAll()
    }

    func refresh(force: Bool = false) async {
        guard !isScanning else { return }
        if !force, let scannedAt, Date().timeIntervalSince(scannedAt) < 600 { return }
        isScanning = true
        error = nil
        let current = revision
        let roots = roots
        let ignores = ignores
        let task = Task.detached(priority: .userInitiated) {
            Self.scan(roots: roots, ignores: ignores, useCache: !force)
        }
        scanTask = task
        let snapshot = await task.value
        guard current == revision, !task.isCancelled else { return }
        scanTask = nil
        isScanning = false
        repositories = snapshot.repositories
        endShow()
        scannedAt = snapshot.date
        error = snapshot.warning
    }

    func loadStatus(_ repo: Repository) async {
        let current = showRevision
        guard !statusPaths.contains(repo.path) else { return }
        while activeStatuses >= 4 {
            do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
            guard current == showRevision else { return }
        }
        guard !Task.isCancelled, current == showRevision, !statusPaths.contains(repo.path) else { return }
        statusPaths.insert(repo.path)
        activeStatuses += 1
        defer { activeStatuses -= 1 }
        if gitLookup == nil {
            gitLookup = Task.detached { await ExecutableLocator.locate("git") }
        }
        guard let git = await gitLookup?.value else { return }
        let path = repo.path
        let result = await Task.detached(priority: .utility) {
            try? await ToolRunner.run(git, ["--no-optional-locks", "-C", path, "status", "--porcelain", "-b"], timeout: 2)
        }.value
        if Task.isCancelled, current == showRevision { statusPaths.remove(path) }
        guard current == showRevision, !Task.isCancelled,
            let result, result.succeeded,
            let index = repositories.firstIndex(where: { $0.path == path }) else { return }
        let lines = result.output.split(whereSeparator: \.isNewline)
        if let headline = lines.first, headline.hasPrefix("## ") {
            var branch = String(headline.dropFirst(3))
            for prefix in ["No commits yet on ", "Initial commit on "] where branch.hasPrefix(prefix) {
                branch = String(branch.dropFirst(prefix.count))
            }
            repositories[index].branch = branch.components(separatedBy: "...")[0]
        }
        repositories[index].isDirty = lines.contains { !$0.hasPrefix("## ") }
    }

    nonisolated private static func scan(roots: [String], ignores: [String], useCache: Bool) -> Snapshot {
        let cache = AppPaths.caches().appending(path: "repos.json")
        if useCache, let data = try? Data(contentsOf: cache),
            let saved = try? JSONDecoder().decode(Snapshot.self, from: data),
            saved.roots == roots, saved.ignores == ignores,
            Date().timeIntervalSince(saved.date) < 600 { return saved }
        let manager = FileManager.default
        let expanded = roots.map { ($0 as NSString).expandingTildeInPath }
        var failed: Set<String> = []
        let repositories = RepoIndexBuilder.build(
            roots: expanded, ignorePatterns: ignores,
            listDirectory: { path in
                guard !Task.isCancelled else { return [] }
                do { return try manager.contentsOfDirectory(atPath: path) } catch { failed.insert(path); return [] }
            },
            readFile: { path in try? String(contentsOfFile: path, encoding: .utf8) },
            isDirectory: { path in
                let values = try? URL(fileURLWithPath: path).resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                return values?.isDirectory == true && values?.isSymbolicLink != true
            })
        var snapshot = Snapshot(roots: roots, ignores: ignores, date: Date(), repositories: repositories)
        let missing = expanded.filter { !manager.fileExists(atPath: $0) }
        if !failed.isEmpty || !missing.isEmpty {
            let paths = Set(missing).union(failed).sorted().joined(separator: ", ")
            snapshot.warning = "Some folders could not be scanned: " + paths
        }
        guard !Task.isCancelled else { return snapshot }
        do {
            try JSONEncoder().encode(snapshot).write(to: cache, options: .atomic)
        } catch {
            snapshot.warning = "Could not save repository cache: \(error.localizedDescription)"
        }
        return snapshot
    }

    deinit { scanTask?.cancel(); gitLookup?.cancel() }
}
