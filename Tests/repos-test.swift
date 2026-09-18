import Foundation

@main
struct ReposTests {
    nonisolated(unsafe) static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() throws {
        try fixtureIndex()
        remotes()
        commands()
        try queriesAndCoding()
        print(failures == 0 ? "Repos tests passed" : "\(failures) repos tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func fixtureIndex() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appending(path: "repos-test-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        func write(_ path: String, _ text: String = "") throws {
            let url = root.appending(path: path)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try write("regular/.git/config", "[remote \"origin\"]\nurl = git@github.com:dev-talix/regular.git\n")
        try write("regular/package.json", #"{"scripts":{"dev":"vite","start":"node app.js"}}"#)
        try write("regular/pnpm-lock.yaml")
        try write("regular/node_modules/nested/.git/HEAD")
        for name in ["first", "second"] {
            try write("regular/.git/worktrees/\(name)/gitdir", root.appending(path: "trees/\(name)/.git").path)
            try write("regular/.git/worktrees/\(name)/commondir", "../..\n")
            try write("trees/\(name)/.git", "gitdir: ../../regular/.git/worktrees/\(name)\n")
        }
        try write("regular/.git/worktrees/stale/gitdir", root.appending(path: "missing/.git").path)
        try write("plain/readme.txt")
        try write("bun/.git/HEAD")
        try write("bun/package.json", #"{"scripts":{"start":"bun app.ts"}}"#)
        try write("bun/bun.lock")
        try write("swift/.git/HEAD")
        try write("swift/Package.swift")
        try write("app-backup-old/.git/HEAD")
        try write("node_modules/ignored/.git/HEAD")
        try write("patchdeck-worktree-backups/ignored/.git/HEAD")
        try write("broken/.git", "gitdir:\n")
        var listedPaths: [String] = []
        let rows = RepoIndexBuilder.build(
            roots: [root.path, root.appending(path: "regular").path],
            ignorePatterns: ["node_modules", "*-backup-*", "patchdeck-worktree-backups"],
            listDirectory: {
                listedPaths.append($0)
                return (try? manager.contentsOfDirectory(atPath: $0)) ?? []
            },
            readFile: { try? String(contentsOfFile: $0, encoding: .utf8) },
            isDirectory: {
                var directory: ObjCBool = false
                return manager.fileExists(atPath: $0, isDirectory: &directory) && directory.boolValue
            }
        )
        expect(rows.count == 5, "index finds three repos and two worktrees, deduplicates overlapping roots")
        expect(rows.filter(\.isWorktree).count == 2, "gitdir and commondir identify worktrees")
        let main = rows.first { $0.name == "regular" }
        expect(main?.devScript == "pnpm run dev", "index detects pnpm dev script")
        expect(main?.org == "dev-talix", "index reads origin config")
        let worktrees = rows.filter(\.isWorktree)
        expect(worktrees.allSatisfy { $0.parentRepoPath == main?.path }, "worktrees retain parent path")
        expect(worktrees.allSatisfy { $0.remoteURL == main?.remoteURL }, "worktrees share origin metadata")
        expect(rows.first { $0.name == "bun" }?.devScript == "bun run start", "bun fixture detection")
        expect(rows.first { $0.name == "swift" }?.devScript == "swift run", "Swift fixture detection")
        expect(rows.allSatisfy { $0.rootPath == root.path }, "root grouping survives external worktree discovery")
        let worktreesPath = root.appending(path: "regular/.git/worktrees").path
        expect(listedPaths.filter { $0 == worktreesPath }.count == 1,
               "main repository and linked worktrees enumerate their common metadata once")
        for name in ["bun", "swift"] {
            expect(!listedPaths.contains(root.appending(path: "\(name)/.git/worktrees").path),
                   "does not enumerate absent optional worktree metadata for \(name)")
        }
        var emptyRootAccesses = 0
        let empty = RepoIndexBuilder.build(
            roots: [], ignorePatterns: [],
            listDirectory: { _ in emptyRootAccesses += 1; return [] },
            readFile: { _ in emptyRootAccesses += 1; return nil },
            isDirectory: { _ in emptyRootAccesses += 1; return false })
        expect(empty.isEmpty, "empty roots produce no repositories")
        expect(emptyRootAccesses == 0, "empty roots do not access the filesystem")
    }

    static func remotes() {
        let expected = RemoteURLParser.Remote(webURL: "https://github.com/team/repo", org: "team")
        expect(RemoteURLParser.parse("git@github.com:team/repo.git") == expected, "SSH shorthand")
        expect(RemoteURLParser.parse("https://github.com/team/repo.git") == expected, "HTTPS remote")
        expect(RemoteURLParser.parse("ssh://git@github.com/team/repo.git") == expected, "SSH URL")
        expect(RemoteURLParser.parse("https://secret:token@github.com/team/repo.git") == expected, "strips credentials")
        expect(RemoteURLParser.parse("file:///tmp/repo") == nil, "local remotes have no web URL")
        expect(RemoteURLParser.parse("not a remote") == nil, "malformed remote")
        expect(RemoteURLParser.parseConfig("[remote \"upstream\"]\nurl = git@github.com:team/repo.git") == nil,
               "does not borrow unrelated remote")
        expect(RemoteURLParser.parse("git@gitlab.com:group/subgroup/repo.git")?.org == "group/subgroup",
               "nested organizations")
    }

    static func commands() {
        let json = #"{"scripts":{"dev":"anything; $(anything)","start":"node app"}}"#
        for (lock, manager) in [("pnpm-lock.yaml", "pnpm"), ("yarn.lock", "yarn"),
                                ("package-lock.json", "npm"), ("bun.lock", "bun"), ("bun.lockb", "bun")] {
            let result = DevCommandDetector.detect(files: ["package.json", lock], packageJSON: json)
            expect(result?.packageManager == manager, "detects \(lock)")
            expect(result?.command == "\(manager) run dev", "uses script name, never script contents")
        }
        expect(DevCommandDetector.detect(files: ["package.json"], packageJSON: "broken") == nil, "invalid JSON")
        expect(DevCommandDetector.detect(files: ["package.json"], packageJSON: "{}") == nil, "missing scripts")
        expect(DevCommandDetector.detect(files: ["package.json"], packageJSON: json)?.command == "npm run dev",
               "no lockfile uses npm")
        expect(DevCommandDetector.detect(files: ["Package.swift"], packageJSON: nil)?.command == "swift run", "Swift")
        expect(DevCommandDetector.detect(files: ["manage.py"], packageJSON: nil)?.command == "python manage.py runserver",
               "Django")
        expect(DevCommandDetector.detect(files: [], packageJSON: nil) == nil, "unknown project")
    }

    static func queriesAndCoding() throws {
        let name = Repository(name: "needle", path: "/name", rootPath: "/")
        let branch = Repository(name: "other", path: "/branch", rootPath: "/", branch: "needle", isWorktree: true)
        let org = Repository(name: "third", path: "/org", rootPath: "/", org: "needle")
        let rows = [org, branch, name]
        expect(RepoQuery.filter(rows, query: "needle", showWorktrees: true).map(\.id) == [name.id, branch.id, org.id],
               "name outranks branch, branch outranks org")
        expect(RepoQuery.filter(rows, query: "ndl", showWorktrees: true).first?.id == name.id, "fuzzy name query")
        expect(RepoQuery.filter(rows, query: "  ", showWorktrees: false).map(\.id) == [org.id, name.id],
               "empty query preserves grouping and hides worktrees")
        expect(RepoQuery.filter(rows, query: "missing", showWorktrees: true).isEmpty, "no query matches")
        let data = try JSONEncoder().encode(rows)
        let decoded = try JSONDecoder().decode([Repository].self, from: data)
        expect(decoded == rows, "repository cache round trip")
    }
}
