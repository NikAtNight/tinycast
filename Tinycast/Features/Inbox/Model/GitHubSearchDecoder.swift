import Foundation

enum GitHubSearchDecoder {
    private struct PullRequest: Decodable {
        struct Repository: Decodable { let nameWithOwner: String }
        let number: Int
        let title: String
        let url: URL
        let repository: Repository
        let state: String
        let updatedAt: Date
        let isDraft: Bool
    }

    private struct Notification: Decodable {
        struct Subject: Decodable { let type: String; let url: URL? }
        struct Repository: Decodable { let full_name: String }
        let subject: Subject
        let repository: Repository
        let unread: Bool
        let updated_at: Date
    }

    static func decode(_ data: Data, section: InboxItem.Section) throws -> [InboxItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([PullRequest].self, from: data).map { pr in
            guard pr.url.scheme == "https", pr.url.host == "github.com", pr.number > 0 else {
                throw CocoaError(.coderInvalidValue)
            }
            return InboxItem(
                id: "github:\(pr.repository.nameWithOwner.lowercased())#\(pr.number)",
                source: .github, title: pr.title,
                subtitle: "\(pr.repository.nameWithOwner) #\(pr.number)", url: pr.url,
                repoOrProject: pr.repository.nameWithOwner, state: pr.isDraft ? "Draft" : pr.state,
                updatedAt: pr.updatedAt, needsAction: section == .review, section: section)
        }
    }

    static func merge(review: [InboxItem], authored: [InboxItem], notifications: Data) throws -> [InboxItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let pages = try decoder.decode([[Notification]].self, from: notifications)
        var updates: [String: Date] = [:]
        for note in pages.flatMap({ $0 }) where note.unread && note.subject.type == "PullRequest" {
            guard let url = note.subject.url, url.host == "api.github.com",
                url.deletingLastPathComponent().lastPathComponent == "pulls",
                let number = Int(url.lastPathComponent)
            else { continue }
            let id = "github:\(note.repository.full_name.lowercased())#\(number)"
            updates[id] = max(updates[id] ?? .distantPast, note.updated_at)
        }
        var seen: Set<String> = []
        return (review + authored).filter { seen.insert($0.id).inserted }.map { original in
            var item = original
            if let updated = updates[item.id] {
                item.needsAction = true
                item.updatedAt = max(item.updatedAt, updated)
            }
            return item
        }
    }
}
