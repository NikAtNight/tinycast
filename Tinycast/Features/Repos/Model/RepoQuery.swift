import Foundation

enum RepoQuery {
    static func filter(_ repositories: [Repository], query: String, showWorktrees: Bool) -> [Repository] {
        let visible = repositories.filter { showWorktrees || !$0.isWorktree }
        let folded = FuzzyMatch.Query(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !folded.isEmpty else { return visible }
        return visible.compactMap { repository -> (Repository, Int)? in
            let scores = [
                FuzzyMatch.score(folded, candidate: repository.name).map { $0 + 300_000 },
                repository.branch.flatMap { FuzzyMatch.score(folded, candidate: $0) }.map { $0 + 200_000 },
                repository.org.flatMap { FuzzyMatch.score(folded, candidate: $0) }.map { $0 + 100_000 }
            ].compactMap { $0 }
            guard let score = scores.max() else { return nil }
            return (repository, score)
        }.sorted {
            $0.1 == $1.1 ? $0.0.path < $1.0.path : $0.1 > $1.1
        }.map(\.0)
    }
}
