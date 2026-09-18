import Foundation

enum RepoIndexBuilder {
    static func build(
        roots: [String], ignorePatterns: [String], listDirectory: (String) -> [String],
        readFile: (String) -> String?, isDirectory: (String) -> Bool
    ) -> [Repository] {
        let ignores = FileSearchIgnoreList(patterns: ignorePatterns)
        var repositories: [String: Repository] = [:]
        var visited: Set<String> = []
        var visitedCommonDirectories: Set<String> = []
        var pending = roots.reversed().map { (path: resolve($0, against: "/"), root: resolve($0, against: "/")) }
        while let directory = pending.popLast() {
            let path = directory.path
            guard !ignores.excludes(path: path), visited.insert(path).inserted, isDirectory(path) else { continue }
            let files = Set(listDirectory(path))
            let gitPath = path + "/.git"
            let gitDirectory: String?
            if isDirectory(gitPath) {
                gitDirectory = gitPath
            } else if let file = readFile(gitPath), file.hasPrefix("gitdir:") {
                let target = file.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines)
                gitDirectory = target.isEmpty ? nil : resolve(target, against: path)
            } else {
                gitDirectory = nil
            }
            guard let gitDirectory, isDirectory(gitDirectory) else {
                for name in files.sorted().reversed() where !name.hasPrefix(".") {
                    pending.append((path + "/" + name, directory.root))
                }
                continue
            }
            let common = readFile(gitDirectory + "/commondir")?.trimmingCharacters(in: .whitespacesAndNewlines)
            let commonDirectory = common.flatMap { $0.isEmpty ? nil : resolve($0, against: gitDirectory) } ?? gitDirectory
            let isWorktree = commonDirectory != gitDirectory
            let parent = isWorktree && commonDirectory.hasSuffix("/.git")
                ? String(commonDirectory.dropLast(5)) : nil
            let remote = readFile(commonDirectory + "/config").flatMap(RemoteURLParser.parseConfig)
            let dev = DevCommandDetector.detect(files: files, packageJSON: readFile(path + "/package.json"))
            repositories[path] = Repository(
                name: URL(fileURLWithPath: path).lastPathComponent, path: path, rootPath: directory.root,
                remoteURL: remote?.webURL, org: remote?.org, isWorktree: isWorktree,
                parentRepoPath: parent, packageManager: dev?.packageManager, devScript: dev?.command
            )
            let worktreesPath = commonDirectory + "/worktrees"
            guard visitedCommonDirectories.insert(commonDirectory).inserted,
                isDirectory(worktreesPath) else { continue }
            for name in listDirectory(worktreesPath).sorted().reversed() {
                guard let raw = readFile(worktreesPath + "/" + name + "/gitdir") else { continue }
                let target = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !target.isEmpty else { continue }
                let gitFile = resolve(target, against: worktreesPath + "/" + name)
                guard gitFile.hasSuffix("/.git"), readFile(gitFile)?.hasPrefix("gitdir:") == true else { continue }
                pending.append((String(gitFile.dropLast(5)), directory.root))
            }
        }
        return repositories.values.sorted {
            if $0.rootPath != $1.rootPath { return $0.rootPath < $1.rootPath }
            let left = $0.parentRepoPath ?? $0.path
            let right = $1.parentRepoPath ?? $1.path
            if left != right { return left < right }
            if $0.isWorktree != $1.isWorktree { return !$0.isWorktree }
            return $0.path < $1.path
        }
    }

    private static func resolve(_ path: String, against base: String) -> String {
        let absolute = path.hasPrefix("/") ? path : base + "/" + path
        return URL(fileURLWithPath: absolute).standardizedFileURL.path
    }
}
