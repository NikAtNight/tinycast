# Kleio

## Invariants

- Kleio's library is a read-only input. Tinycast never changes a recording or caches its text.
- Model files take document data, URLs and query text as parameters. They do no filesystem work
  and never open a URL.
- `AppCore` owns `KleioStore` and `KleioCoordinator`. Library reads run off main.
- A trigger never hands focus to Kleio. `KleioLauncher` opens every `kleio://` URL with
  `activates` set to false, and the palette hides before the URL is sent.
- Return copies the full transcript through `Paster`, whose marker keeps the copy out of clipboard
  history. Empty transcripts leave the clipboard alone.
- Closing the palette releases loaded recordings. Reopening reads the library again.
- Fixtures contain synthetic text only. Errors never quote transcript contents.

## Commands

The Kleio feature owns six `CommandID` cases. They are ordinary Commands settings entries with the
existing visibility and hotkey controls; `CommandID.hotKeyAction` already returns `.command(self)`
for every built-in that is not query-driven, so each is bindable to a global chord with no extra
`HotKeyAction` case. There is no new launcher section or settings pane.

| Command | URL sent | HUD on success |
| --- | --- | --- |
| Start Kleio Meeting Recording | `kleio://record/start?mode=meeting` | Kleio: starting meeting recording |
| Start Kleio Voice Memo | `kleio://record/start?mode=mic` | Kleio: starting voice memo |
| Stop Kleio Recording | `kleio://record/stop` | Kleio: stopping recording |
| Toggle Kleio Recording | `kleio://record/toggle?mode=meeting` | Kleio: toggling meeting recording |
| Toggle Kleio Dictation | `kleio://dictation/toggle` | Kleio: toggling dictation |
| Kleio Recordings | none | opens `PaletteMode.kleioRecordings` |

`LauncherCoordinator.runCommand` calls `KleioCoordinator.trigger` with a `KleioCommandURL` case, or
`show()` for the list. `KleioCommandURL` is the only place the scheme is spelled; `mode` accepts
`meeting`, `system` or `mic`. Kleio (bundle id `app.talix.scribe`) registers the scheme.

`KleioLauncher` asks `NSWorkspace.urlForApplication(toOpen:)` first. A nil answer means Kleio is not
installed or its build does not register `kleio://` yet, and the coordinator reports that through
`reportFailure`. Any other open error shows a danger HUD. A newer trigger cancels the HUD of an older
one still in flight.

## Recordings screen

`RootPaletteView` creates `KleioRecordingsScreen`, which ranks `KleioStore.recordings` with
`KleioQuery`: fuzzy matching over titles and full text, newest first on a blank query, and a
200-row cap applied after filtering so an older recording can still match. `KleioRecordingsView`
injects the coordinator into its hierarchy, loads the library while the palette is visible, and
releases it when the palette hides or the view disappears.

Return and double-click copy the transcript; Command-Return does the same. The Command-K menu adds
Show in Finder, which reveals the recording folder, and Copy Segment Range, which opens first/last
segment steppers in the preview. Segment numbers are inclusive and start at one in the UI. Copy Range
copies the chosen segments in document order.

## Reading the library

`AppCore` injects `~/Library/Application Support/Scribe/library`. Kleio kept the old folder name
when it was renamed, so the path still says Scribe.

The store reads each child directory's `document.json` once per load. `KleioDocumentDecoder` uses
`id`, `title`, ISO 8601 `createdAt`, `duration` and `segments`; each segment has text, start and end
seconds and an optional speaker. Other metadata is ignored. Malformed JSON, a blank id, a bad date and
invalid timing values reject that one file. Other recordings still appear and the screen reports the
failure count. A missing or unreadable library shows a message instead of rows.

There is no directory watcher. `load` tags each read with a request identity, so a load that was
cancelled, or superseded by `release`, publishes nothing.

## Verification

`Tests/kleio-test.swift` covers the decoder (valid documents, missing speakers, segment ranges and
every rejected shape), `KleioQuery` ranking and limits, every `KleioCommandURL` string, and
`KleioStore` over a synthetic temporary tree: a missing library, stray files, hidden folders,
malformed neighbours, release and cancellation. It never reads the real library.

```sh
./Scripts/run-tests.sh kleio-test
```

Sending a real trigger needs a Kleio build that registers the scheme, so that half is a manual check:
bind a chord, press it with another app frontmost, and confirm Kleio reacts without coming forward.

## Out of scope

Editing transcripts, deleting recordings, network access and settings backups of transcript text.
Modes other than `meeting` and `mic` have no command yet; `KleioCommandURL` already accepts `system`.
