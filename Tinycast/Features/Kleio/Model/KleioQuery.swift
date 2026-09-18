import Foundation

enum KleioQuery {
    static let resultLimit = 200

    static func rank(_ recordings: [KleioRecording], for query: String) -> [KleioRecording] {
        let folded = FuzzyMatch.Query(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return recordings.compactMap { recording -> (KleioRecording, Int)? in
            if folded.isEmpty { return (recording, 0) }
            let score = [recording.title, recording.text]
                .compactMap { FuzzyMatch.score(folded, candidate: $0) }.max()
            return score.map { (recording, $0) }
        }.sorted { left, right in
            if left.1 != right.1 { return left.1 > right.1 }
            if left.0.date != right.0.date { return left.0.date > right.0.date }
            return left.0.id < right.0.id
        }.prefix(resultLimit).map(\.0)
    }
}
