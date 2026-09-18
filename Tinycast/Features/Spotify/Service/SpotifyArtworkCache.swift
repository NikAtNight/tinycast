import Foundation

/// Row artwork on disk under `Caches/<bundle-id>/spotify-artwork/<id>.jpg`, fetched once.
enum SpotifyArtworkCache {
    nonisolated static var directory: URL {
        AppPaths.caches().appendingPathComponent("spotify-artwork", isDirectory: true)
    }

    /// The cached file's path, downloading on the store's session first; nil when neither works.
    nonisolated static func path(id: String, url: URL) async -> String? {
        let file = directory.appendingPathComponent(id).appendingPathExtension("jpg")
        if FileManager.default.fileExists(atPath: file.path) { return file.path }
        guard let (data, response) = try? await SpotifyStore.session.data(from: url),
            (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty
        else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard (try? data.write(to: file, options: .atomic)) != nil else { return nil }
        return file.path
    }
}
