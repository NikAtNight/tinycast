import Foundation

struct InboxItem: Codable, Equatable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable { case github, jira }
    enum Section: String, Codable, CaseIterable, Sendable {
        case review = "Needs my review"
        case authored = "My PRs"
        case jira = "Jira"
    }

    let id: String
    let source: Source
    let title: String
    let subtitle: String
    let url: URL
    let repoOrProject: String
    let state: String
    var updatedAt: Date
    var needsAction: Bool
    let section: Section

    func isUnread(readThrough: [String: Date]) -> Bool {
        needsAction && (readThrough[id].map { $0 < updatedAt } ?? true)
    }

    static func ordered(_ items: [InboxItem], query: String) -> [InboxItem] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return Section.allCases.flatMap { section in
            items.filter { item in
                item.section == section && terms.allSatisfy { term in
                    [item.title, item.subtitle, item.repoOrProject].contains {
                        $0.localizedCaseInsensitiveContains(term)
                    }
                }
            }.sorted { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt }
        }
    }
}
