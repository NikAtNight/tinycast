import AppKit

/// Starts playback in the Spotify desktop app; the same detached AppleScript shape as Finder info.
enum SpotifyPlayer {
    static func play(uri: String) async -> Bool {
        guard let source = SpotifyPlayScript.source(uri: uri) else { return false }
        return await Task.detached(priority: .userInitiated) {
            guard let script = NSAppleScript(source: source) else { return false }
            var errorInfo: NSDictionary?
            script.executeAndReturnError(&errorInfo)
            return errorInfo == nil
        }.value
    }
}
