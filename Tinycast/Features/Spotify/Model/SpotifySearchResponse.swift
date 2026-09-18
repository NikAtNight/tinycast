import Foundation

/// The Web API's `/v1/search` body, reduced to what a row needs. Unknown fields are ignored.
struct SpotifySearchResponse: Decodable, Sendable {
    /// Spotify returns `null` for playlist items it will not serve, so every page admits gaps.
    struct Page<Item: Decodable & Sendable>: Decodable, Sendable {
        let items: [Item?]
    }

    struct Image: Decodable, Sendable {
        let url: String
        let width: Int?
        let height: Int?
    }

    struct ExternalURLs: Decodable, Sendable {
        let spotify: String?
    }

    struct ArtistName: Decodable, Sendable {
        let name: String
    }

    struct Owner: Decodable, Sendable {
        let displayName: String?
    }

    struct Track: Decodable, Sendable {
        let id: String
        let uri: String
        let name: String
        let artists: [ArtistName]?
        let album: Album?
        let externalUrls: ExternalURLs?
    }

    struct Artist: Decodable, Sendable {
        let id: String
        let uri: String
        let name: String
        let images: [Image]?
        let externalUrls: ExternalURLs?
    }

    struct Album: Decodable, Sendable {
        let id: String
        let uri: String
        let name: String
        let artists: [ArtistName]?
        let images: [Image]?
        let releaseDate: String?
        let externalUrls: ExternalURLs?
    }

    struct Playlist: Decodable, Sendable {
        let id: String
        let uri: String
        let name: String
        let owner: Owner?
        let images: [Image]?
        let externalUrls: ExternalURLs?
    }

    let tracks: Page<Track>?
    let artists: Page<Artist>?
    let albums: Page<Album>?
    let playlists: Page<Playlist>?

    static func decode(_ data: Data) throws -> SpotifySearchResponse {
        try decoder.decode(SpotifySearchResponse.self, from: data)
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

/// The client-credentials grant's answer; `expiresIn` is seconds from receipt.
struct SpotifyTokenResponse: Decodable, Sendable {
    let accessToken: String
    let expiresIn: Double

    static func decode(_ data: Data) throws -> SpotifyTokenResponse {
        try SpotifySearchResponse.decoder.decode(SpotifyTokenResponse.self, from: data)
    }
}

extension SpotifySearchResults {
    /// The artwork the row caches at 64 px: the smallest image that still covers it.
    static let artworkSide = 64

    init(response: SpotifySearchResponse) {
        tracks = (response.tracks?.items ?? []).compactMap { $0 }.map { track in
            let artists = (track.artists ?? []).map(\.name).joined(separator: ", ")
            let subtitle = [artists, track.album?.name ?? ""].filter { !$0.isEmpty }
                .joined(separator: " · ")
            return SpotifyItem(
                id: track.id, uri: track.uri, name: track.name,
                subtitle: subtitle.isEmpty ? SpotifyItem.Kind.track.label : subtitle, kind: .track,
                artworkURL: Self.artworkURL(from: track.album?.images),
                externalURL: Self.externalURL(track.externalUrls, kind: .track, id: track.id))
        }
        artists = (response.artists?.items ?? []).compactMap { $0 }.map { artist in
            SpotifyItem(
                id: artist.id, uri: artist.uri, name: artist.name,
                subtitle: SpotifyItem.Kind.artist.label, kind: .artist,
                artworkURL: Self.artworkURL(from: artist.images),
                externalURL: Self.externalURL(artist.externalUrls, kind: .artist, id: artist.id))
        }
        albums = (response.albums?.items ?? []).compactMap { $0 }.map { album in
            let artists = (album.artists ?? []).map(\.name).joined(separator: ", ")
            let year = String((album.releaseDate ?? "").prefix(4))
            let subtitle = [artists, year].filter { !$0.isEmpty }.joined(separator: " · ")
            return SpotifyItem(
                id: album.id, uri: album.uri, name: album.name,
                subtitle: subtitle.isEmpty ? SpotifyItem.Kind.album.label : subtitle, kind: .album,
                artworkURL: Self.artworkURL(from: album.images),
                externalURL: Self.externalURL(album.externalUrls, kind: .album, id: album.id))
        }
        playlists = (response.playlists?.items ?? []).compactMap { $0 }.map { playlist in
            let owner = playlist.owner?.displayName ?? ""
            return SpotifyItem(
                id: playlist.id, uri: playlist.uri, name: playlist.name,
                subtitle: owner.isEmpty ? SpotifyItem.Kind.playlist.label : "By \(owner)",
                kind: .playlist, artworkURL: Self.artworkURL(from: playlist.images),
                externalURL: Self.externalURL(playlist.externalUrls, kind: .playlist, id: playlist.id))
        }
    }

    /// Spotify lists images largest first; the row wants the smallest one at or above 64 px.
    static func artworkURL(from images: [SpotifySearchResponse.Image]?) -> URL? {
        guard let images, !images.isEmpty else { return nil }
        let sized = images.compactMap { image -> (side: Int, url: URL)? in
            guard let url = URL(string: image.url), url.scheme == "https" else { return nil }
            return (max(image.width ?? 0, image.height ?? 0), url)
        }
        let covering = sized.filter { $0.side >= artworkSide }.min { $0.side < $1.side }
        return (covering ?? sized.max { $0.side < $1.side })?.url
    }

    /// The web link Spotify sent, or the canonical one built from the id when it sent none.
    static func externalURL(
        _ external: SpotifySearchResponse.ExternalURLs?, kind: SpotifyItem.Kind, id: String
    ) -> URL {
        if let spotify = external?.spotify, let url = URL(string: spotify), url.scheme == "https" {
            return url
        }
        return URL(string: "https://open.spotify.com/\(kind.rawValue)/\(id)")!
    }
}
