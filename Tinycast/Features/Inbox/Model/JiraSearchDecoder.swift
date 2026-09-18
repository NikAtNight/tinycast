import Foundation

enum JiraSearchDecoder {
    struct Page: Sendable {
        let items: [InboxItem]
        let nextPageToken: String?
    }

    private struct Response: Decodable {
        struct Issue: Decodable {
            struct Fields: Decodable {
                struct Status: Decodable { let name: String }
                struct Project: Decodable { let key: String }
                let summary: String
                let status: Status
                let project: Project
                let updated: String
            }
            let id: String
            let key: String
            let fields: Fields
        }
        let issues: [Issue]
        let isLast: Bool
        let nextPageToken: String?
    }

    static func decode(_ data: Data, site: URL) throws -> Page {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.isLast || response.nextPageToken?.isEmpty == false else {
            throw CocoaError(.coderInvalidValue)
        }
        let dateFormat = DateFormatter()
        dateFormat.locale = Locale(identifier: "en_US_POSIX")
        dateFormat.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        let items = try response.issues.map { issue in
            guard let updated = dateFormat.date(from: issue.fields.updated) else {
                throw CocoaError(.coderInvalidValue)
            }
            return InboxItem(
                id: "jira:\(site.host ?? ""):\(issue.id)", source: .jira,
                title: issue.fields.summary, subtitle: issue.key,
                url: site.appending(path: "browse").appending(component: issue.key),
                repoOrProject: issue.fields.project.key, state: issue.fields.status.name,
                updatedAt: updated, needsAction: true, section: .jira)
        }
        return Page(items: items, nextPageToken: response.isLast ? nil : response.nextPageToken)
    }
}
