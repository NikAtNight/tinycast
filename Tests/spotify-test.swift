// Spotify's pure half: response decoding, the row mapper, request shapes, the token expiry
// margin, the play script guard, and the session's debounce and cancellation through a stub.
// Nothing here reaches the network.

import Foundation

@main
@MainActor
struct SpotifyTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async throws {
        try decoding()
        try mapper()
        requests()
        tokens()
        errors()
        playScript()
        await session()
        print(failures == 0 ? "Spotify tests passed" : "\(failures) Spotify tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// Shaped from the Web API reference for `GET /v1/search`, with synthetic ids and names.
    static let fixture = Data("""
    {
      "tracks": {
        "href": "https://api.spotify.com/v1/search?query=whisper&type=track&offset=0&limit=8",
        "limit": 8, "next": null, "offset": 0, "previous": null, "total": 1,
        "items": [
          {
            "album": {
              "album_type": "album", "total_tracks": 10,
              "external_urls": {"spotify": "https://open.spotify.com/album/alb00000000000000001"},
              "id": "alb00000000000000001",
              "images": [
                {"url": "https://i.scdn.co/image/large", "height": 640, "width": 640},
                {"url": "https://i.scdn.co/image/medium", "height": 300, "width": 300},
                {"url": "https://i.scdn.co/image/small", "height": 64, "width": 64}
              ],
              "name": "Night Songs", "release_date": "2019-05-03", "release_date_precision": "day",
              "type": "album", "uri": "spotify:album:alb00000000000000001",
              "artists": [{"id": "art00000000000000001", "name": "Synthetic Artist", "type": "artist"}]
            },
            "artists": [
              {"external_urls": {"spotify": "https://open.spotify.com/artist/art00000000000000001"},
               "id": "art00000000000000001", "name": "Synthetic Artist", "type": "artist",
               "uri": "spotify:artist:art00000000000000001"},
              {"id": "art00000000000000002", "name": "Second Voice", "type": "artist",
               "uri": "spotify:artist:art00000000000000002"}
            ],
            "disc_number": 1, "duration_ms": 213000, "explicit": false,
            "external_urls": {"spotify": "https://open.spotify.com/track/trk00000000000000001"},
            "id": "trk00000000000000001", "is_local": false, "name": "Whisper My Name",
            "popularity": 40, "track_number": 3, "type": "track",
            "uri": "spotify:track:trk00000000000000001"
          }
        ]
      },
      "artists": {
        "limit": 8, "offset": 0, "total": 1,
        "items": [
          {
            "external_urls": {"spotify": "https://open.spotify.com/artist/art00000000000000001"},
            "followers": {"href": null, "total": 12},
            "genres": ["ambient"], "id": "art00000000000000001",
            "images": [{"url": "https://i.scdn.co/image/artist-160", "height": 160, "width": 160}],
            "name": "Synthetic Artist", "popularity": 10, "type": "artist",
            "uri": "spotify:artist:art00000000000000001"
          }
        ]
      },
      "albums": {
        "limit": 8, "offset": 0, "total": 1,
        "items": [
          {
            "album_type": "single", "total_tracks": 1,
            "id": "alb00000000000000002", "images": [],
            "name": "Bare Single", "release_date": "2021", "release_date_precision": "year",
            "type": "album", "uri": "spotify:album:alb00000000000000002",
            "artists": [{"id": "art00000000000000001", "name": "Synthetic Artist", "type": "artist"}]
          }
        ]
      },
      "playlists": {
        "limit": 8, "offset": 0, "total": 2,
        "items": [
          null,
          {
            "collaborative": false, "description": "Quiet evenings",
            "external_urls": {"spotify": "https://open.spotify.com/playlist/pls00000000000000001"},
            "id": "pls00000000000000001",
            "images": [{"url": "https://i.scdn.co/image/playlist", "height": null, "width": null}],
            "name": "Late Night", "owner": {"display_name": "Listener", "id": "listener"},
            "public": true, "type": "playlist", "uri": "spotify:playlist:pls00000000000000001"
          }
        ]
      }
    }
    """.utf8)

    static func decoding() throws {
        let response = try SpotifySearchResponse.decode(fixture)
        expect(response.tracks?.items.count == 1, "one track decodes")
        expect(response.tracks?.items.first??.album?.images?.count == 3, "album images decode with sizes")
        expect(response.artists?.items.first??.name == "Synthetic Artist", "artist name decodes")
        expect(response.albums?.items.first??.releaseDate == "2021", "release_date maps from snake case")
        expect(response.playlists?.items.count == 2, "a null playlist item is kept as a gap, not an error")
        expect(response.playlists?.items.first! == nil, "the null playlist decodes as nil")
        expect(response.playlists?.items.last??.owner?.displayName == "Listener", "owner display_name decodes")

        let partial = try SpotifySearchResponse.decode(Data(#"{"tracks":{"items":[]}}"#.utf8))
        expect(partial.tracks?.items.isEmpty == true && partial.artists == nil, "absent sections decode as nil")

        let token = try SpotifyTokenResponse.decode(
            Data(#"{"access_token":"tok","token_type":"Bearer","expires_in":3600}"#.utf8))
        expect(token.accessToken == "tok" && token.expiresIn == 3600, "the token response decodes")

        for data in [Data(), Data("{".utf8), Data(#"{"tracks":{"items":[{"name":"no id"}]}}"#.utf8)] {
            expect((try? SpotifySearchResponse.decode(data)) == nil, "malformed bodies throw")
        }
    }

    static func mapper() throws {
        let results = SpotifySearchResults(response: try SpotifySearchResponse.decode(fixture))
        expect(results.all.map(\.kind) == [.track, .artist, .album, .playlist], "rows follow section order")
        expect(results.all.count == 4, "the null playlist produces no row")

        let track = results.tracks[0]
        expect(track.id == "trk00000000000000001" && track.uri == "spotify:track:trk00000000000000001", "track identity")
        expect(track.subtitle == "Synthetic Artist, Second Voice · Night Songs", "track subtitle lists artists and album")
        expect(track.artworkURL?.absoluteString == "https://i.scdn.co/image/small", "a track takes the 64 px album image")
        expect(track.externalURL.absoluteString == "https://open.spotify.com/track/trk00000000000000001",
               "the external link is Spotify's own")

        let artist = results.artists[0]
        expect(artist.subtitle == "Artist", "an artist's subtitle names its kind")
        expect(artist.artworkURL?.absoluteString == "https://i.scdn.co/image/artist-160",
               "the smallest image at or above 64 px is chosen")

        let album = results.albums[0]
        expect(album.subtitle == "Synthetic Artist · 2021", "an album subtitle is artists and year")
        expect(album.artworkURL == nil, "no images means no artwork")
        expect(album.externalURL.absoluteString == "https://open.spotify.com/album/alb00000000000000002",
               "a missing external link is built from the id")

        let playlist = results.playlists[0]
        expect(playlist.subtitle == "By Listener", "a playlist subtitle names its owner")
        expect(playlist.artworkURL?.absoluteString == "https://i.scdn.co/image/playlist",
               "an unsized image is still used when it is the only one")

        let tiny = [SpotifySearchResponse.Image(url: "https://i.scdn.co/image/t", width: 32, height: 32)]
        expect(SpotifySearchResults.artworkURL(from: tiny)?.absoluteString == "https://i.scdn.co/image/t",
               "when nothing covers 64 px the largest image is used")
        let insecure = [SpotifySearchResponse.Image(url: "http://example.com/a.jpg", width: 64, height: 64)]
        expect(SpotifySearchResults.artworkURL(from: insecure) == nil, "artwork is only fetched over https")
        expect(SpotifySearchResults.empty.isEmpty && results.items(of: .track) == results.tracks,
               "empty and per-kind accessors agree with the sections")
    }

    static func requests() {
        let token = SpotifyAPI.tokenRequest(clientID: "id", clientSecret: "secret")
        expect(token.url == SpotifyAPI.tokenEndpoint && token.httpMethod == "POST", "the token request posts to accounts")
        expect(token.httpBody == Data("grant_type=client_credentials".utf8), "the grant is client credentials")
        expect(token.value(forHTTPHeaderField: "Authorization") == "Basic aWQ6c2VjcmV0",
               "the id and secret ride as HTTP basic auth")
        expect(token.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded",
               "the body is form encoded")

        let search = SpotifyAPI.searchRequest(query: "whisper my name", token: "tok")
        let components = URLComponents(url: search.url!, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        expect(components.host == "api.spotify.com" && components.path == "/v1/search", "search hits /v1/search")
        expect(items["q"] == "whisper my name", "the query rides as q")
        expect(items["type"] == "track,artist,album,playlist", "all four types are asked for")
        expect(items["limit"] == "8", "eight per type")
        expect(search.url!.absoluteString.contains("q=whisper%20my%20name"), "spaces are percent encoded, never plus")
        expect(search.value(forHTTPHeaderField: "Authorization") == "Bearer tok", "the search carries the bearer token")

        expect(SpotifyAPI.normalizedQuery("  ") == nil, "whitespace is never searched")
        expect(SpotifyAPI.normalizedQuery("\n radiohead ") == "radiohead", "queries are trimmed")
    }

    static func tokens() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let token = SpotifyAccessToken(
            response: SpotifyTokenResponse(accessToken: "tok", expiresIn: 3600), now: now)
        expect(token.expiresAt == now.addingTimeInterval(3600), "expiry is receipt plus expires_in")
        expect(token.isUsable(at: now), "a fresh token is usable")
        expect(token.isUsable(at: now.addingTimeInterval(3600 - 61)), "usable while more than a minute remains")
        expect(!token.isUsable(at: now.addingTimeInterval(3600 - 60)), "refreshed once inside the last minute")
        expect(!token.isUsable(at: now.addingTimeInterval(3600)), "an expired token is never used")
        expect(!token.isUsable(at: now.addingTimeInterval(7200)), "a long-expired token is never used")
        expect(SpotifyAccessToken.refreshMargin == 60, "the margin is sixty seconds")
    }

    static func errors() {
        expect(SpotifySearchError(status: 401) == .unauthorized, "401 is unauthorized")
        expect(SpotifySearchError(status: 400) == .unauthorized, "the token endpoint's 400 reads as unauthorized")
        expect(SpotifySearchError(status: 403) == .unauthorized, "403 is unauthorized")
        expect(SpotifySearchError(status: 429) == .rateLimited, "429 is rate limited")
        expect(SpotifySearchError(status: 503) == .http(503), "other statuses keep their number")
        let messages = [SpotifySearchError.missingCredentials, .unauthorized, .rateLimited, .offline, .http(500), .malformed]
            .map(\.message)
        expect(Set(messages).count == messages.count && messages.allSatisfy { !$0.isEmpty }, "every error has its own message")
    }

    static func playScript() {
        expect(SpotifyPlayScript.source(uri: "spotify:track:trk00000000000000001")
               == "tell application \"Spotify\" to play track \"spotify:track:trk00000000000000001\"",
               "a track URI becomes the play script")
        for kind in ["artist", "album", "playlist"] {
            expect(SpotifyPlayScript.source(uri: "spotify:\(kind):abc123") != nil, "\(kind) URIs play through the same form")
        }
        for bad in ["", "spotify:track:", "spotify:show:abc", "spotify:track:abc\" & quit", "https://open.spotify.com/track/x",
                    "spotify:track:abc\n"] {
            expect(SpotifyPlayScript.source(uri: bad) == nil, "\(bad.debugDescription) never reaches AppleScript")
        }
    }

    /// A stub in place of the store: records what was asked, answers after an optional delay.
    @MainActor
    final class Stub {
        var asked: [String] = []
        var cancelled: [String] = []
        var delay: Duration = .zero
        var failing: SpotifySearchError?

        func perform(_ query: String) async throws -> SpotifySearchResults {
            asked.append(query)
            do {
                try await Task.sleep(for: delay)
            } catch {
                cancelled.append(query)
                throw error
            }
            if let failing { throw failing }
            let item = SpotifyItem(
                id: query, uri: "spotify:track:\(query)", name: query, subtitle: "Track", kind: .track,
                artworkURL: nil, externalURL: URL(string: "https://open.spotify.com/track/\(query)")!)
            return SpotifySearchResults(tracks: [item])
        }
    }

    static func session() async {
        let stub = Stub()
        let session = SpotifySearchSession(debounce: .milliseconds(20), perform: stub.perform)

        session.search("   ")
        try? await Task.sleep(for: .milliseconds(60))
        expect(stub.asked.isEmpty, "an empty query never searches")
        expect(session.results.isEmpty && session.error == nil, "an empty query publishes nothing")

        session.search("a")
        session.search("ab")
        session.search("abc")
        try? await Task.sleep(for: .milliseconds(80))
        expect(stub.asked == ["abc"], "typing inside the debounce searches once, for the last query, got \(stub.asked)")
        expect(session.results.tracks.first?.name == "abc" && session.query == "abc", "the last query publishes")
        expect(!session.isSearching, "isSearching clears after the answer lands")

        stub.asked = []
        stub.delay = .milliseconds(200)
        session.search("slow")
        try? await Task.sleep(for: .milliseconds(60))
        expect(stub.asked == ["slow"] && session.isSearching, "a debounced query is in flight")
        stub.delay = .zero
        session.search("fast")
        try? await Task.sleep(for: .milliseconds(250))
        expect(stub.cancelled == ["slow"], "a superseded request is cancelled, got \(stub.cancelled)")
        expect(session.results.tracks.first?.name == "fast", "only the newest query publishes")
        expect(session.query == "fast" && !session.isSearching, "the session settles on the newest query")

        stub.asked = []
        stub.failing = .rateLimited
        session.search("limited")
        try? await Task.sleep(for: .milliseconds(80))
        expect(session.error == SpotifySearchError.rateLimited.message, "a failure publishes its message inline")
        expect(session.results.isEmpty, "a failed search drops the previous rows")
        stub.failing = nil

        session.search("again")
        try? await Task.sleep(for: .milliseconds(80))
        expect(session.error == nil && session.results.tracks.first?.name == "again", "a later success clears the error")

        session.search("cleared")
        session.search("")
        try? await Task.sleep(for: .milliseconds(80))
        expect(!stub.asked.contains("cleared"), "clearing inside the debounce cancels the pending search")
        expect(session.results.isEmpty && session.query.isEmpty, "clearing empties the rows")

        stub.delay = .milliseconds(200)
        session.search("reset")
        try? await Task.sleep(for: .milliseconds(60))
        session.reset()
        try? await Task.sleep(for: .milliseconds(250))
        expect(stub.cancelled.contains("reset"), "reset cancels the in-flight request")
        expect(session.results.isEmpty && session.error == nil && !session.isSearching, "reset publishes nothing")
    }
}
