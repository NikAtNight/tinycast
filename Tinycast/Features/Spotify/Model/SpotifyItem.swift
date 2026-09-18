import Foundation

/// One search hit, flattened so a row and an action never care which Spotify object it came from.
struct SpotifyItem: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case track
        case artist
        case album
        case playlist

        var sectionTitle: String {
            switch self {
            case .track: return "Tracks"
            case .artist: return "Artists"
            case .album: return "Albums"
            case .playlist: return "Playlists"
            }
        }

        var label: String {
            switch self {
            case .track: return "Track"
            case .artist: return "Artist"
            case .album: return "Album"
            case .playlist: return "Playlist"
            }
        }

        /// The row's glyph until artwork lands, and its only glyph when Spotify sends none.
        var symbol: String {
            switch self {
            case .track: return "music.note"
            case .artist: return "music.microphone"
            case .album: return "square.stack"
            case .playlist: return "music.note.list"
            }
        }
    }

    let id: String
    let uri: String
    let name: String
    let subtitle: String
    let kind: Kind
    let artworkURL: URL?
    let externalURL: URL
}

/// The four sections a search answers with, in the order the screen lists them.
struct SpotifySearchResults: Equatable, Sendable {
    var tracks: [SpotifyItem] = []
    var artists: [SpotifyItem] = []
    var albums: [SpotifyItem] = []
    var playlists: [SpotifyItem] = []

    static let empty = SpotifySearchResults()

    var isEmpty: Bool { all.isEmpty }

    /// The flat row order the palette selection indexes.
    var all: [SpotifyItem] { tracks + artists + albums + playlists }

    func items(of kind: SpotifyItem.Kind) -> [SpotifyItem] {
        switch kind {
        case .track: return tracks
        case .artist: return artists
        case .album: return albums
        case .playlist: return playlists
        }
    }
}
