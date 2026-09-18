import Foundation

enum PortsQuery {
    static func rank(_ ports: [ListeningPort], for query: String) -> [ListeningPort] {
        let query = FuzzyMatch.Query(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return ports.compactMap { item -> (ListeningPort, Int)? in
            if query.isEmpty { return (item, 0) }
            let fields = [String(item.port), item.command, item.directoryName ?? ""]
            guard let score = fields.compactMap({ FuzzyMatch.score(query, candidate: $0) }).max()
            else { return nil }
            return (item, score)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.0.port != $1.0.port { return $0.0.port < $1.0.port }
            return $0.0.pid < $1.0.pid
        }.map(\.0)
    }
}
