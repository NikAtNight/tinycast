import Foundation

enum DevCommandDetector {
    struct Command: Equatable, Sendable {
        let packageManager: String?
        let command: String
    }

    static func detect(files: Set<String>, packageJSON: String?) -> Command? {
        if files.contains("package.json"), let data = packageJSON?.data(using: .utf8),
           let package = try? JSONDecoder().decode(Package.self, from: data),
           let script = ["dev", "start"].first(where: { !(package.scripts?[$0] ?? "").isEmpty }) {
            let manager: String
            if files.contains("pnpm-lock.yaml") {
                manager = "pnpm"
            } else if files.contains("yarn.lock") {
                manager = "yarn"
            } else if files.contains("package-lock.json") {
                manager = "npm"
            } else if files.contains("bun.lock") || files.contains("bun.lockb") {
                manager = "bun"
            } else {
                manager = "npm"
            }
            return Command(packageManager: manager, command: "\(manager) run \(script)")
        }
        if files.contains("Package.swift") {
            return Command(packageManager: nil, command: "swift run")
        }
        if files.contains("manage.py") {
            return Command(packageManager: nil, command: "python manage.py runserver")
        }
        return nil
    }

    private struct Package: Decodable {
        let scripts: [String: String]?
    }
}
