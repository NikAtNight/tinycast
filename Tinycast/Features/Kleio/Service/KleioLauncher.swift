import AppKit

/// Sends one `kleio://` trigger without activating Kleio, so focus stays where the launcher left it.
@MainActor
struct KleioLauncher {
    enum Failure: Error {
        case notInstalled
    }

    func open(_ command: KleioCommandURL) async throws {
        let url = command.url
        guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else { throw Failure.notInstalled }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        _ = try await NSWorkspace.shared.open(url, configuration: configuration)
    }
}
