# Transcripts

## Invariants

- LocalFlow and Scribe files are read-only inputs. Tinycast never changes them or caches their text.
- Model files take text, data, source URLs and a calendar as parameters. They do no filesystem work.
- `AppCore` owns `TranscriptStore` and `TranscriptsCoordinator`. Reads and file watches run off main.
- Dictation Return pastes through `Paster` into the app captured when the palette opened.
  Scribe Return copies the full transcript. Copies use Paster's marker to avoid clipboard recapture.
- Closing the palette cancels watches and releases loaded transcripts. Reopening reads the files again.
- Fixtures contain synthetic text only. Errors never quote transcript contents.

## Commands and screens

Phase 7 of [the fork plan](../fork-plan.md) is the requirement source. The Transcripts feature owns
these commands, which remain ordinary Commands settings entries with the existing visibility and
hotkey controls. There is no new launcher section or settings pane.

| Command | Result |
| --- | --- |
| Open Today's Dictation History | Opens today's LocalFlow Markdown file with `NSWorkspace` |
| Paste Last Dictation | Reads today's file afresh and pastes its last nonempty entry |
| Dictation History | Opens `PaletteMode.dictationHistory`, newest matches first |
| Scribe Recordings | Opens `PaletteMode.scribeRecordings`, with title, date and duration |

`LauncherCoordinator.runCommand` calls the coordinator. `RootPaletteView` creates `TranscriptsScreen`,
which uses `TranscriptQuery` for fuzzy matching over titles and full text. The 200-row limit applies
after filtering, so an older entry can still match. `TranscriptsView` injects the coordinator into its
view hierarchy and observes the store only while the palette is visible.

Return and double-click perform the primary action. Command-Return copies. The Command-K menu also
reveals the source file or recording folder. Scribe's Copy Segment Range action opens first/last
segment controls in the preview. Segment numbers are inclusive and start at one in the UI.
The Copy Range button copies their text in document order. Empty transcripts leave the clipboard alone.

## Reading and live updates

The store receives both directories from `AppCore`:

- `~/Library/Application Support/LocalFlow/History`
- `~/Library/Application Support/Scribe/library`

LocalFlow files begin with `# Dictations YYYY-MM-DD`. Each `## HH:MM:SS` starts an entry whose body
continues until the next heading. Paragraph breaks remain intact. The injected calendar interprets
local wall-clock times. Invalid timestamps and empty bodies produce no entry.

Scribe reads each child directory's `document.json`. The decoder uses `id`, `title`, ISO 8601
`createdAt`, `duration` and `segments`. Each segment has text, start/end seconds and an optional speaker.
Additional recording metadata is ignored. Malformed JSON and invalid timing values reject that file.
One bad file does not prevent other recordings from appearing; the screen reports the failure count.

The LocalFlow observer arms DispatchSource watches before reading. It watches the directory and each
Markdown file to catch both atomic replacements and in-place appends. Events coalesce, then rebuild
the watches and reread. If the history folder is absent, the nearest existing ancestor is watched so
creating the folder can recover without relaunching. Missing or unreadable directories show a message.
Scribe refreshes each time its screen opens. Request identities prevent a cancelled observer from
publishing over a newer screen.

## Verification

`Tests/transcripts-test.swift` covers empty files, one entry, multiple paragraphs, bad timestamps,
malformed JSON, invalid segment ranges, fuzzy matching and result limits. Run:

```sh
./Scripts/run-tests.sh transcripts-test
```

The service check uses an isolated temporary tree for append, replacement, new files, missing-directory
recovery, cancellation and source switching. It never reads either real application directory.

```sh
./Scripts/run-tests.sh transcripts-store-test
```

## Out of scope

Toggling dictation needs a URL scheme such as `localflow://toggle` added to LocalFlow itself.
Tinycast does not synthesize that capability. Starting Scribe recordings, editing transcripts,
network access and settings backups of transcript text are also outside this feature.
