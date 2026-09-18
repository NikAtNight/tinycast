import Foundation

@main
struct InboxTests {
    static func main() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "inbox-fixtures")
        func fixture(_ name: String) throws -> Data { try Data(contentsOf: root.appending(path: name + ".json")) }
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            checks += 1
            guard condition() else { print("FAIL: \(label)"); exit(1) }
        }
        func rejects(_ label: String, _ operation: () throws -> Void) {
            do { try operation(); check(false, label) } catch { check(true, label) }
        }
        let authored = try GitHubSearchDecoder.decode(fixture("github-authored"), section: .authored)
        let review = try GitHubSearchDecoder.decode(fixture("github-review"), section: .review)
        check(review.isEmpty, "Captured review search is empty")
        check(authored.count == 1, "Captured authored PR decoded")
        check(authored[0].id == "github:example/launcher#42", "Stable repository and PR identity")
        check(!authored[0].needsAction, "Authored PR starts read")
        let requested = try GitHubSearchDecoder.decode(fixture("github-authored"), section: .review)
        let merged = try GitHubSearchDecoder.merge(
            review: requested, authored: authored, notifications: fixture("github-notifications"))
        check(merged.count == 1 && merged[0].section == .review, "Review takes precedence on overlap")
        let activity = try GitHubSearchDecoder.merge(review: [], authored: authored,
                                                   notifications: fixture("github-notifications"))
        check(activity[0].needsAction, "Notification marks authored PR unread")
        let note = Data("""
            [[{"unread":true,"updated_at":"2030-01-01T00:00:00Z",
            "subject":{"type":"PullRequest","url":"https://api.github.com/repos/example/launcher/pulls/42"},
            "repository":{"full_name":"example/launcher"}}]]
            """.utf8)
        let updated = try GitHubSearchDecoder.merge(review: [], authored: authored, notifications: note)[0]
        check(updated.updatedAt > authored[0].updatedAt, "New comments advance update timestamp")
        check(updated.isUnread(readThrough: [:]), "New activity is unread")
        check(!updated.isUnread(readThrough: [updated.id: updated.updatedAt]), "Mark read survives same update")
        check(updated.isUnread(readThrough: [updated.id: authored[0].updatedAt]), "Later activity becomes unread")
        let nullNote = Data("""
            [[{"unread":true,"updated_at":"2030-01-01T00:00:00Z",
            "subject":{"type":"PullRequest","url":null},"repository":{"full_name":"example/launcher"}}]]
            """.utf8)
        let unchanged = try GitHubSearchDecoder.merge(review: [], authored: authored, notifications: nullNote)
        check(unchanged == authored, "Null notification URL ignored")
        let site = URL(string: "https://example.atlassian.net")!
        let jira = try JiraSearchDecoder.decode(fixture("jira-search"), site: site)
        check(jira.items.count == 2 && jira.nextPageToken == nil, "Jira final page")
        check(jira.items[0].url.absoluteString == "https://example.atlassian.net/browse/SXCL-42", "Jira browser URL")
        check(jira.items[0].updatedAt > jira.items[1].updatedAt, "Jira timestamp honors offset")
        check(jira.items[0].repoOrProject == "SXCL" && jira.items[0].state == "In Progress", "Jira metadata")
        let next = try JiraSearchDecoder.decode(
            Data("{\"issues\":[],\"isLast\":false,\"nextPageToken\":\"abc\"}".utf8), site: site)
        check(next.nextPageToken == "abc", "Jira pagination token")
        rejects("Missing Jira pagination token fails") {
            _ = try JiraSearchDecoder.decode(Data("{\"issues\":[],\"isLast\":false}".utf8), site: site)
        }
        rejects("Malformed GitHub fails") { _ = try GitHubSearchDecoder.decode(Data("{}".utf8), section: .review) }
        rejects("Malformed Jira fails") { _ = try JiraSearchDecoder.decode(Data("{}".utf8), site: site) }
        let raw = String(bytes: try fixture("github-authored"), encoding: .utf8)!
        rejects("Non-browser PR URL rejected") {
            _ = try GitHubSearchDecoder.decode(Data(raw.replacingOccurrences(of: "https://github.com", with: "file://").utf8),
                                               section: .review)
        }
        check(InboxItem.ordered(authored + jira.items, query: "focus SXCL").count == 1, "Search matches all terms")
        check(InboxItem.ordered(jira.items + authored, query: "").first?.source == .github, "Stable section order")
        let organizations = try InboxPreferences.organizations(from: "NikAtNight, dev-talix NIKATNIGHT")
        check(organizations == ["NikAtNight", "dev-talix"], "Owners normalized and deduplicated")
        let emptyOwners = try InboxPreferences.organizations(from: "")
        check(emptyOwners.isEmpty, "Empty owners stay empty")
        rejects("Query injection rejected") { _ = try InboxPreferences.organizations(from: "foo OR author:other") }
        let encoded = try JSONEncoder().encode(updated)
        let decoded = try JSONDecoder().decode(InboxItem.self, from: encoded)
        check(decoded == updated, "Snapshot round trip")
        print("PASS: \(checks) Inbox checks")
    }
}
