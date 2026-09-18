## Invariants

- ClipShare accepts video only. Every source goes through AVFoundation to a temporary MP4.
- Model files take directory listings and sizes as inputs. They do no filesystem or network IO.
- The client uses a private ephemeral session without a URL cache or cookie store.
- The token stays in Tinycast's channel-specific Keychain scope `clipshare.token`, under one fixed
  UUID account. It never enters defaults, logs or backups. No ClipShare.app credentials are read.
- Source files are never changed. Exported videos and temporary part files are removed after use.
- Only an explicit command uploads a file. There is no directory watcher or background upload queue.
- Delete and revoke require Tinycast's confirmation dialog. Revoke replaces the old link.

## Commands and settings

`AppCore` owns `ClipShareCoordinator`, created in `start()` and stopped on termination.
`LauncherCoordinator.runCommand` routes three `CommandID` cases to it:

- **Share Latest Recording** reads the screenshot location with `defaults read com.apple.screencapture
  location`, or uses `~/Desktop` when unset. It selects the newest regular MOV or MP4 by modification
  time, ignoring case. A missing configured directory reports an error.
- **Share File on Clipboard** reads the first file URL from the pasteboard. AVFoundation rejects
  sources without a readable video track, including screenshots.
- **Recent ClipShare Uploads** opens `PaletteMode.clipShareRecent`, fetching the newest 20 records.
  Search filters their titles and original filenames locally. Return copies a ready video's URL;
  Command-Return opens it. Command-K offers copy, open, revoke, delete and refresh. Unfinished rows
  expose their actions on Return so they can still be deleted.

The ClipShare settings pane saves the base URL in channel-local defaults under `clipshare.baseURL`.
It defaults to `https://clips.talix.app`. A blank token preserves the saved token; Remove Saved Token
removes it. Connection details stay outside settings backups. The Commands pane owns the commands'
visibility and hotkey controls. Views receive the coordinator through the environment.

## Upload path

The coordinator reads the credential before starting a background-priority detached task. The task
finds the source and calls `ClipShareMediaExporter.prepare`. H.264 video with AAC or no audio takes
passthrough export; other codecs take a transcode preset. Export optimizes the MP4 for network use.
The upload request uses the exported size and dimensions with the original filename.

`ClipShareClient` creates the record with one idempotency key, reads its status, uploads missing
1-based parts with exact Content-Length and octet-stream bodies, then completes it. The server's
part size drives `ClipShareUploadPlan`. Parts stream through temporary files in bounded chunks.
The HUD reports export progress and completed-part upload progress. Success copies the share URL.

Retryable network/server errors get three attempts with status reads between attempts. An accepted
part whose response was lost is skipped on retry. A lost create response reuses the idempotency key.
The client also accepts an explicit resume ID. The UI resumes within the current upload only; quitting
or exhausting retries discards the prepared file. An unfinished remote record can be deleted from
Recent Uploads. There is no persistent resume journal.

Errors clear the progress HUD and use `reportFailure`. Missing credentials explain where to paste a
token. Changing the connection cancels any pending recent-list fetch so old-server rows cannot appear
under a new connection. HTTPS is required except for loopback development servers.

## Verification

Requirement source: fork plan Phase 6 and the ClipShare API contract. ClipShare owns this flow;
worker/API changes and screenshot uploads are out of scope.

`Tests/clipshare-test.swift` compiles the shipped models and client, and drives
`Tests/clipshare-fixtures/server.js` on a random loopback port. It checks part boundaries, invalid
sizes, newest-video selection, API decoding, exact multipart bytes, lost responses, explicit resume,
recent records, revoke, delete and rejected credentials. Fixtures never call the production API.

Run `./Scripts/run-tests.sh clipshare-test`, the full suite, lint and the Debug build as described in
`docs/testing.md`. Live uploads need a user-supplied token and were not exercised during development.

### Development check, 2026-09-18

Verified on this worktree with macOS 27 and Xcode 27, before commit:

- ClipShare harness passed, including PNG rejection, temporary-file cleanup and cancellation.
- Full suite ran all 77 harnesses. 69 passed. Failures were file-search, clipboard, clipboard-text,
  pasteboard, custom-command, snippets, notes and notes-editor. Diagnostics included unavailable
  system services, file replacement errors and Vision pixel-buffer creation failure. Icon-cache
  passed in this restricted environment. These failures need a rerun outside this sandbox.
- Lint and model purity passed. The final diff has no whitespace errors.
- The normal build failed at Icon Studio export. A build with only command-line overrides
  `EXCLUDED_SOURCE_FILE_NAMES=tinycast.icon ASSETCATALOG_COMPILER_APPICON_NAME=` and
  `OTHER_SWIFT_FLAGS=-disable-sandbox` passed. No project settings changed for these overrides.
- The test runner needed `TINYCAST_TEST_JOBS=2` because `sysctl` was denied, a worktree-local
  `TMPDIR`, and a local compiler wrapper supplying the SDK path and `-disable-sandbox` for macros.
- App launch failed through LaunchServices and aborted when invoked directly. Successful movie
  export, rendered UI, Keychain persistence and live API behavior remain unverified.
- Git could not create the parent repository's worktree `index.lock`, so this record describes
  an uncommitted diff. Build/test logs are `/tmp/tinycast-clipshare-{build-final,tests-isolated,
  focused,lint-final}.log` on the development machine.
