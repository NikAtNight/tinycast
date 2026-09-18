import Foundation

enum GitHubInboxSource {
    enum SourceError: LocalizedError {
        case unavailable, failed, missingBranch
        var errorDescription: String? {
            switch self {
            case .unavailable: "GitHub CLI was not found. Install gh and sign in with gh auth login."
            case .failed: "GitHub could not refresh. Check gh auth status and your network connection."
            case .missingBranch: "GitHub returned no branch name for this pull request."
            }
        }
    }

    nonisolated static func fetch(executable: URL, organizations: [String]) async throws -> [InboxItem] {
        guard !organizations.isEmpty else { return [] }
        let common = ["--state=open", "--limit=1000", "--sort=updated", "--order=desc", "--json",
                      "number,title,url,repository,state,updatedAt,isDraft"]
            + organizations.map { "--owner=\($0)" }
        async let review = run(executable, ["search", "prs", "--review-requested=@me"] + common)
        async let authored = run(executable, ["search", "prs", "--author=@me"] + common)
        async let notifications = run(executable, ["api", "--method", "GET", "notifications?per_page=50",
                                                   "--paginate", "--slurp"])
        return try await GitHubSearchDecoder.merge(
            review: GitHubSearchDecoder.decode(review, section: .review),
            authored: GitHubSearchDecoder.decode(authored, section: .authored), notifications: notifications)
    }

    nonisolated static func branch(executable: URL, item: InboxItem) async throws -> String {
        struct Branch: Decodable { let headRefName: String }
        let data = try await run(executable, ["pr", "view", item.url.absoluteString, "--json", "headRefName"])
        let branch = try JSONDecoder().decode(Branch.self, from: data).headRefName
        guard !branch.isEmpty else { throw SourceError.missingBranch }
        return branch
    }

    nonisolated private static func run(_ executable: URL, _ arguments: [String]) async throws -> Data {
        let result = try await ToolRunner.run(executable, arguments, timeout: 10)
        guard result.succeeded else { throw SourceError.failed }
        return Data(result.output.utf8)
    }
}
