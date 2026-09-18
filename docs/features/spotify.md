# Spotify

Search Spotify is a palette screen that searches the Spotify Web API and plays the chosen result
in the Spotify desktop app. A `spotify:search:` quicklink only opens Spotify's own search view with
the query mangled and never plays anything; this screen replaces that.

## Invariants

- **Credentials live only in the login Keychain**, under the scopes `spotify.clientID` and
  `spotify.clientSecret` with one fixed account each. Neither enters `UserDefaults`, logs, errors or
  a settings backup. There is no `AppSettingsKey` for either, so `SettingsBackupCoverage` has nothing
  to exclude: a backup cannot carry them because nothing outside Keychain holds them.
- **The token is held in memory only.** `SpotifyStore` fetches it through the client-credentials
  grant and replaces it once fewer than `SpotifyAccessToken.refreshMargin` (60 s) remain. A 401 on a
  search drops it so the next search fetches afresh. Nothing writes it to disk.
- **Every request rides `SpotifyStore.session`**, a private `.ephemeral` session with `urlCache`
  and cookie storage nil, never `URLSession.shared`. Artwork under
  `Caches/<bundle-id>/spotify-artwork/<id>.jpg` is the only copy Tinycast keeps.
- **An empty query is never sent.** `SpotifySearchSession` trims first, debounces typing by 250 ms,
  keeps one request in flight and cancels it when the query changes. A result that lost the race
  never publishes; `spotify-test` pins this through a stub.
- **`Model/` is Foundation only** and takes the response bytes, the clock and the credentials as
  parameters. `SpotifyPlayScript.source(uri:)` refuses anything but a plain Spotify URI, so no text
  can reach AppleScript unquoted.
- **Errors show inline in the screen, never as a dialog.** Missing credentials show an empty state
  with Open Spotify Settings; 401, 429 and offline show `SpotifySearchError.message` in place of the
  rows. Only a play failure reaches a HUD, through `core.showMessage(tone: .danger)`.
- **Playing hides the palette first.** ↵ runs `tell application "Spotify" to play track "<uri>"`
  through `NSAppleScript` inside `Task.detached`, the same shape as `AppLauncher.showInfoInFinder`;
  one form serves track, artist, album and playlist URIs.

## Wiring

`CommandID.spotifySearch` ("Search Spotify", `music.note.list`) opens `PaletteMode.spotify`.
`AppCore` owns `SpotifyStore`, `SpotifySearchSession` (its `perform` is the store's `search`) and
`SpotifyCoordinator`, and calls `spotify.start()` in `start()` to read credential presence off main.
`RootPaletteView` builds `SpotifyScreen` from the coordinator.

Search Spotify is also a launcher fallback, `Fallback.Builtin.spotifySearch`, offered while the
command's Settings checkbox is on, the same rule Define follows. `FallbackCoordinator.run` hands
the typed query to `SpotifyCoordinator.show(query:)`, which seeds the screen the way Search Files
does.

## Screen

`SpotifyScreen.rows` is `SpotifySearchResults.all`: tracks, then artists, albums and playlists, at
most eight of each. `SpotifyView` draws one `SectionHeader` per non-empty kind; headers take no
selection index. A row shows the 64 px artwork through `EntryIconView(.artwork)` once
`SpotifyArtworkCache` has it on disk, and the kind's symbol until then or when Spotify sent none.

| Action | Chord | What it does |
| --- | --- | --- |
| Play | ↵ | hides the palette and plays the URI in Spotify.app; a failure shows a danger HUD |
| Open in Spotify | ⌘↵ | opens the `spotify:` URI with `NSWorkspace`, so the app shows the item |
| Copy Spotify Link | ⌘K | the `open.spotify.com` link through `Paster` |
| Copy URI | ⌘K | the `spotify:` URI through `Paster` |

Hiding the palette resets the session, so a re-summon searches the typed query again rather than
showing rows from a previous visit.

## Settings

Settings › Spotify holds Client ID and Client Secret fields, Save, Remove and Test Connection, plus
the standard `FeatureCommandsSection`. The id is prefilled from Keychain; the secret is never read
back, and leaving it blank on Save keeps the saved one. Test Connection fetches a fresh token and
reports the verdict inline beside the button. `SettingsTab.ownedCommands` names the pane, so
Settings › Commands neither lists the command nor gates it behind Enable Commands.

Credentials come from an app registered at developer.spotify.com. The client-credentials grant
needs no user login and cannot control playback through the Web API, which is why playback goes
through AppleScript instead.

## Verification

```sh
./Scripts/run-tests.sh spotify-test
```

The harness compiles `Spotify/Model/*` and `SpotifySearchSession`. It decodes a hand-written
fixture shaped from the search reference, including a `null` playlist item, checks the mapper's
subtitles, artwork choice and external links, pins both request shapes, the 60 s token margin,
the status-to-error mapping and the play script guard, and drives the session's debounce,
supersession, failure and reset paths through a stub. It never calls Spotify.

Manual: save real credentials, type a query, confirm four sections with artwork, ↵ plays in
Spotify.app, ⌘↵ shows the item there, and a wrong secret reads as rejected credentials inline.

## Out of scope

Playback control beyond starting an item, user-scoped API calls, and a search results cache.
