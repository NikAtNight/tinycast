import AppKit

@MainActor
enum RepoOpener {
    enum Failure: LocalizedError {
        case tool(String)
        var errorDescription: String? {
            switch self {
            case .tool(let message): message
            }
        }
    }

    static func supacode(_ repository: Repository) async throws {
        let known = URL(fileURLWithPath: "/Applications/supacode.app/Contents/Resources/bin/supacode")
        let executable = await Task.detached { () async -> URL? in
            if FileManager.default.isExecutableFile(atPath: known.path) { return known }
            return await ExecutableLocator.locate("supacode")
        }.value
        guard let executable else {
            var link = URLComponents()
            link.scheme = "supacode"
            link.host = "repo"
            link.path = "/open"
            link.queryItems = [URLQueryItem(name: "path", value: repository.path)]
            guard let url = link.url else { throw Failure.tool("Could not construct Supacode URL.") }
            _ = try await NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        let path = repository.path
        let result = try await Task.detached {
            try await ToolRunner.run(executable, ["repo", "open", path, "--timeout", "10"], timeout: 12)
        }.value
        guard result.succeeded else { throw Failure.tool(result.tail) }
    }

    static var ghosttyInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Ghostty.app")
            || NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty") != nil
    }

    static func ghostty(_ repository: Repository, command: String? = nil) async throws {
        let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty")
            ?? URL(fileURLWithPath: "/Applications/Ghostty.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--working-directory=\(repository.path)"]
        if let command { configuration.arguments += ["-e", command] }
        _ = try await NSWorkspace.shared.openApplication(at: application, configuration: configuration)
    }

    static func remote(_ repository: Repository) async throws {
        guard let text = repository.remoteURL, let url = URL(string: text),
            ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw Failure.tool("This repository has no web remote.")
        }
        _ = try await NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
    }
}
