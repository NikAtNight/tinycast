import Foundation

@MainActor
@Observable
final class TalixStore {
    struct Running: Codable, Sendable {
        let environment: TalixEnvironment
        var timer: TalixTimer
        var pendingEntry: TalixTimeEntry?
        var rate: Double?
        var billable: Bool?
    }

    struct ListedEntry: Identifiable {
        let project: TalixProject
        let entry: TalixTimeEntry
        var id: String { project.id + ":" + (entry.id ?? entry.startTime ?? entry.description) }
    }

    private struct Cache: Codable, Sendable {
        let environment: TalixEnvironment
        let fetchedAt: Date
        let projects: [TalixProject]
    }

    private(set) var projects: [TalixProject] = []
    private(set) var entries: [ListedEntry] = []
    private(set) var running: Running?
    private(set) var isLoading = false
    private(set) var isReady = false
    private(set) var errorMessage: String?
    private(set) var environment: TalixEnvironment?
    private var fetchedAt: Date?
    private var client: TalixClient?
    private let cacheURL: URL
    private let timerURL: URL
    @ObservationIgnored private var loading: Task<Void, Never>?

    init(cacheURL: URL? = nil, timerURL: URL? = nil) {
        self.cacheURL = cacheURL ?? AppPaths.caches().appendingPathComponent("talix-projects.json")
        self.timerURL = timerURL ?? AppPaths.applicationSupport().appendingPathComponent("talix-timer.json")
    }

    func start() {
        guard loading == nil else { return }
        let timerURL = timerURL
        loading = Task { [weak self] in
            do {
                let running = try await Task.detached {
                    guard FileManager.default.fileExists(atPath: timerURL.path) else { return Running?.none }
                    return try JSONDecoder().decode(Running.self, from: Data(contentsOf: timerURL))
                }.value
                self?.running = running
                self?.isReady = true
            } catch {
                self?.errorMessage = "Could not restore the Talix timer. Its saved file has been preserved."
            }
        }
    }

    func restore() async {
        start()
        await loading?.value
    }

    func refresh(environment: TalixEnvironment, force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        await restore()
        if self.environment != environment {
            self.environment = environment
            client = TalixClient(environment: environment)
            projects = []
            entries = []
            fetchedAt = nil
            let cacheURL = cacheURL
            if let cache = await Task.detached(operation: {
                try? JSONDecoder().decode(Cache.self, from: Data(contentsOf: cacheURL))
            }).value, cache.environment == environment {
                projects = cache.projects
                fetchedAt = cache.fetchedAt
            }
        }
        guard let client else { return }
        do {
            if force || fetchedAt.map({ Date().timeIntervalSince($0) >= 86400 }) != false {
                projects = try await client.projects()
                fetchedAt = Date()
                let cache = Cache(environment: environment, fetchedAt: Date(), projects: projects)
                let cacheURL = cacheURL
                try await Task.detached {
                    try JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
                }.value
            }
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = .current
            let day = String(formatter.string(from: Date()).prefix(10))
            var listed: [ListedEntry] = []
            for project in projects {
                let items = try await client.entries(projectId: project.id, day: day)
                listed += items.map { ListedEntry(project: project, entry: $0) }
            }
            entries = listed.sorted { ($0.entry.startTime ?? "") > ($1.entry.startTime ?? "") }
            if isReady { errorMessage = nil }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setRunning(_ value: Running?) async throws {
        guard isReady else { throw TalixRPC.RPCError.rejected }
        let timerURL = timerURL
        try await Task.detached {
            if let value {
                try JSONEncoder().encode(value).write(to: timerURL, options: .atomic)
            } else if FileManager.default.fileExists(atPath: timerURL.path) {
                try FileManager.default.removeItem(at: timerURL)
            }
        }.value
        running = value
    }

    func create(projectId: String, entry: TalixTimeEntry, environment: TalixEnvironment) async throws {
        let client = self.environment == environment ? self.client : nil
        _ = try await (client ?? TalixClient(environment: environment)).create(projectId: projectId, entry: entry)
    }

    func invalidateProjects() async throws {
        let cacheURL = cacheURL
        try await Task.detached {
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                try FileManager.default.removeItem(at: cacheURL)
            }
        }.value
        client = nil
        environment = nil
        fetchedAt = nil
        entries = []
        projects = []
    }
}
