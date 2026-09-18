import Foundation

enum TranscriptQuery {
    static let resultLimit = 200

    static func rank(_ entries: [TranscriptEntry], for query: String) -> [TranscriptEntry] {
        let folded = FuzzyMatch.Query(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return entries.compactMap { entry -> (TranscriptEntry, Int)? in
            if folded.isEmpty { return (entry, 0) }
            let score = [entry.title, entry.text].compactMap { FuzzyMatch.score(folded, candidate: $0) }.max()
            return score.map { (entry, $0) }
        }.sorted { left, right in
            if left.1 != right.1 { return left.1 > right.1 }
            if left.0.date != right.0.date { return left.0.date > right.0.date }
            return left.0.id < right.0.id
        }.prefix(resultLimit).map(\.0)
    }
}
