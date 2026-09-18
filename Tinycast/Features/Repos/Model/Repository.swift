import Foundation

struct Repository: Codable, Hashable, Identifiable, Sendable {
    var id: String { path }
    var name: String
    var path: String
    var rootPath: String
    var remoteURL: String?
    var org: String?
    var branch: String?
    var isDirty: Bool?
    var isWorktree: Bool
    var parentRepoPath: String?
    var packageManager: String?
    var devScript: String?

    init(
        name: String, path: String, rootPath: String, remoteURL: String? = nil,
        org: String? = nil, branch: String? = nil, isDirty: Bool? = nil,
        isWorktree: Bool = false, parentRepoPath: String? = nil,
        packageManager: String? = nil, devScript: String? = nil
    ) {
        self.name = name
        self.path = path
        self.rootPath = rootPath
        self.remoteURL = remoteURL
        self.org = org
        self.branch = branch
        self.isDirty = isDirty
        self.isWorktree = isWorktree
        self.parentRepoPath = parentRepoPath
        self.packageManager = packageManager
        self.devScript = devScript
    }
}
