import Foundation

/// Owns when a search runs: debounced typing, one request in flight, and no stale publish.
@MainActor
@Observable
final class SpotifySearchSession {
    typealias Perform = @MainActor (String) async throws -> SpotifySearchResults

    private(set) var results = SpotifySearchResults.empty
    /// The inline message, nil while the last search answered or nothing has been asked.
    private(set) var error: String?
    private(set) var isSearching = false
    /// The query the published rows answer; empty once reset.
    private(set) var query = ""

    private let perform: Perform
    private let debounce: Duration
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Bumped per request, so a task that lost the race cannot publish or clear `isSearching`.
    @ObservationIgnored private var generation = 0

    init(debounce: Duration = SpotifyAPI.debounce, perform: @escaping Perform) {
        self.debounce = debounce
        self.perform = perform
    }

    func search(_ raw: String) {
        task?.cancel()
        generation += 1
        guard let query = SpotifyAPI.normalizedQuery(raw) else {
            clear()
            return
        }
        let request = generation
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: debounce)
            } catch {
                return
            }
            guard generation == request else { return }
            isSearching = true
            do {
                let found = try await perform(query)
                guard generation == request, !Task.isCancelled else { return }
                self.query = query
                results = found
                self.error = nil
            } catch is CancellationError {
                return
            } catch {
                guard generation == request, !Task.isCancelled else { return }
                self.query = query
                results = .empty
                self.error = (error as? SpotifySearchError)?.message ?? SpotifySearchError.offline.message
            }
            isSearching = false
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        generation += 1
        clear()
    }

    private func clear() {
        query = ""
        results = .empty
        error = nil
        isSearching = false
    }
}
