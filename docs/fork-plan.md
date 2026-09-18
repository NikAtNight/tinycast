# Fork plan: Nikhil's Tinycast

What we are adding to the fork, in what order, and how each piece fits Tinycast's architecture.
Everything here was checked against the code on 2026-09-18. Repo rules in `AGENTS.md` and
`docs/architecture.md` still apply to every feature below.

## Ground truth that shapes the plan

Tinycast facts (see `docs/architecture.md`, `docs/features/*.md`):

- One feature = one folder under `Tinycast/Features/<Name>/` with `Model/` (Foundation only,
  everything injected), `Service/` (effects), `UI/` (screens + coordinator), `Settings/`.
- A launcher row is an `AppEntry` with a `Kind`. Adding a Kind touches `AppIndex.swift` (case,
  descriptor, slice, setter, `publishEntries()` order) and `LauncherList.rows`.
- A full-screen list (like File Search) is a `PaletteMode` case + a `PaletteScreen` conformer +
  a branch in `RootPaletteView.screen`. Row actions are `PopoverMenuContent` (the ⌘K menu).
- Inline "keyword then argument" input already exists: quicklinks accept `{argument}` tokens and
  render an argument strip in the launcher. A third argument-taking feature adds its own
  `<Feature>ArgumentsAccessory` and a branch in `LauncherScreen.headerAccessory`.
- Shell commands run through `ShellCommandRunner` (`/bin/zsh -lc`, positional args, no timeout,
  output in Tinycast's own window). Finding a binary on PATH is `Platform/ExecutableLocator`.
  Short tool calls with a timeout go through `ToolRunner.run`.
- Networked features copy `CurrencyRateStore` exactly: private ephemeral session, cache in
  `AppPaths.caches()`, one refresh loop. Secrets go in `KeychainSecretStore`, never in defaults.
- Built-in commands get a global hotkey for free by adding a `CommandID` case. Per-record
  hotkeys need a `HotKeyAction` case and the `AppCore.start()` wiring.
- Definition of done: `./Scripts/run-tests.sh`, `./Scripts/lint.sh`, purity grep empty, clean
  Debug build with no new warnings, docs fixed in the same commit.

Nikhil's tools (checked on disk):

| Tool | Control surface a launcher can use |
| --- | --- |
| Talix | Streamable HTTP MCP at `https://api.talix.app/api/mcp`, `Authorization: Bearer tlx_…`. Tools: `list_projects`, `list_time_entries`, `get_report`, `create_time_entry`, `update_time_entry`. Entry needs `projectId, description, date, startTime, endTime, rate, billable`. REST is WorkOS-session only, so MCP is the path. |
| ClipShare | HTTP at `https://clips.talix.app`, bearer token, multipart video upload (`POST /api/videos` → `PUT parts` → `complete` → `shareUrl`). No CLI, no URL scheme. Token lives in ClipShare's own Keychain item. |
| LocalFlow | No trigger of any kind. Transcripts at `~/Library/Application Support/LocalFlow/History/YYYY-MM-DD.md`. |
| Scribe | Source repo no longer on disk, app not installed. Data at `~/Library/Application Support/Scribe/library/<uuid>/document.json`. |
| File Cleanup | GUI app at `~/Applications/File Cleanup.app`, LaunchAgent `com.nikhlkapadia.cleanup-desktop-screenshots`. No CLI. |
| Supacode | CLI at `/Applications/supacode.app/Contents/Resources/bin/supacode` (not on PATH), plus `supacode://` deeplinks. |
| Hermes kanban | CLI `~/.local/bin/{hermes,sxcl,olive}` over a local SQLite DB. |
| GitHub | `gh` at `/opt/homebrew/bin/gh`, logged in as NikAtNight. Orgs: NikAtNight, dev-talix, ServiceXcelerator, olivehq. |
| Jira | No CLI, no stored creds. pi has a `/jira` extension expecting `~/.pi/jira.json` (absent). Project key `SXCL`. |
| Repos | `~/Talix`, `~/SXCL`, `~/Olive`, `~/Repo`, `~/gateway`. Heavy worktree use (kleio 38, localflow 22, portillos 19, dashboard 11, invoicing 9). |
| Obsidian | One vault "Notes" in iCloud. Folders `00 Nigel` … `07 Others`. `obsidian://` URI works. |
| Spotify | Installed, no API creds. AppleScript + `spotify:` URIs. |
| Terminal / browser | Ghostty, Zen. |
| Ollama | Running, `gemma3:4b` and `s1-mini`. |

## Phase 0: setup and branch strategy

1. Create the `Tinycast Self-Signed` identity (docs/signing.md §1). Without it every signed build
   fails and macOS forgets the Accessibility grant on each rebuild. Unsigned builds
   (`CODE_SIGNING_ALLOWED=NO`) already succeed with two pre-existing warnings in
   `ClipboardView.swift:284`. Those two are the baseline, not ours.
2. `brew install xcodegen swiftlint`. Both are missing and both are required by the definition of
   done. Node is present.
3. Baseline on clean `main` (2026-09-18, macOS 27.0, Xcode 27.0): signed Debug build succeeds,
   `./Scripts/lint.sh` is clean, and `./Scripts/run-tests.sh` passes 75 of 76. `icon-cache-test`
   fails upstream on this machine (five "final-size bytes match" checks against the System
   Settings icon), so it is not ours to fix and not a regression if it keeps failing.
4. Branches: `main` tracks `upstream/main` and never gets feature commits. Each feature is a
   `feat/<name>` branch, merged into `main` of the fork by PR. Sync upstream with
   `git fetch upstream && git merge upstream/main` on `main` first, then rebase open feature
   branches. New code stays in its own `Features/<Name>/` folder. The unavoidable shared touch
   points, and therefore the only likely merge conflicts, are: `AppIndex.swift`,
   `PaletteMode.swift`, `RootPaletteView.swift`, `AppCore.swift`, `SettingsTab.swift`,
   `SettingsDetailView.swift`, `SettingsSearchCatalog.swift`, `CommandID.swift`,
   `LauncherCoordinator.runCommand`, `Scripts/run-tests.sh`.

## Phase 1: zero-code wins (quicklinks and custom commands)

These need no Swift. Enter them in Settings, then export a settings backup and commit it under
`docs/nikhil-presets/` so they can be re-imported on a fresh machine. The template engine
percent-encodes argument values automatically for URL destinations; fixed parts of a URL must
already be encoded (`%20` for spaces in folder names).

Quicklinks (name → link):

| Name | Link |
| --- | --- |
| Google | `https://www.google.com/search?q={argument name="Query"}` |
| YouTube | `https://www.youtube.com/results?search_query={argument name="Query"}` |
| Spotify search | `spotify:search:{argument name="Song or artist"}` |
| GitHub search | `https://github.com/search?q={argument name="Query"}&type=code` |
| Obsidian open note | `obsidian://open?vault=Notes&file={argument name="Note"}` |
| Obsidian daily | `obsidian://daily?vault=Notes` |
| Obsidian new research note | `obsidian://new?vault=Notes&file=03%20Research%20Notes/{argument name="Title"}` |
| Obsidian new work note | `obsidian://new?vault=Notes&file=04%20Work/{argument name="Title"}` |
| Obsidian new journal note | `obsidian://new?vault=Notes&file=01%20Journal/{date format="yyyy-MM-dd"}` |
| Jira ticket | `https://<site>.atlassian.net/browse/{argument name="Key" default="SXCL-"}` (site URL still unknown, see Jira section) |

Add one quicklink per remaining Obsidian folder the same way. `obsidian://new` also accepts
`&content=` for a body argument if wanted.

Custom shell commands (name → command):

| Name | Command |
| --- | --- |
| Spotify play/pause | `osascript -e 'tell application "Spotify" to playpause'` |
| Spotify next | `osascript -e 'tell application "Spotify" to next track'` |
| Spotify now playing | `osascript -e 'tell application "Spotify" to (name of current track) & " · " & (artist of current track)'` (shows in the confirmation pill) |
| Run screenshot cleanup now | `launchctl kickstart gui/$(id -u)/com.nikhlkapadia.cleanup-desktop-screenshots` |
| Open File Cleanup | `open "$HOME/Applications/File Cleanup.app"` |
| Cleanup log | `tail -n 40 ~/.local/var/log/cleanup-desktop-screenshots.log` (show output on) |
| Open dictation history | `open "$HOME/Library/Application Support/LocalFlow/History/$(date +%F).md"` |
| Supacode open | `/Applications/supacode.app/Contents/Resources/bin/supacode open` |
| New SXCL card | `sxcl kanban create "$1" --workspace dir:"$2"` with two arguments (title, path) |

Rule of thumb for later phases: if a thing is one shell line with at most two arguments, it stays
a custom command. Only things that need a list, a cache, a secret, or structured data become a
Swift feature.

## Phase 2: Ports (Port & Process killer)

Smallest real feature. It teaches `PaletteMode`, `PaletteScreen`, row actions, and `ToolRunner`
before anything harder. Logic comes from `pi-extensions/extensions/devwatch.ts` lines 163-199.

Folder `Features/Ports/`:

- `Model/ListeningPort.swift`: `struct ListeningPort { port, pid, command, address, cwd? }`.
- `Model/LsofParser.swift`: pure `parse(_ output: String) -> [ListeningPort]` for
  `lsof -nP -iTCP -sTCP:LISTEN +c0`, trailing `:PORT`, dedupe by `pid:port` to collapse v4/v6.
  Also `parseCwd(_ output: String)` for `lsof -a -p <pid> -d cwd -Fn` (line starting with `n`).
- `Model/PortsQuery.swift`: fuzzy filter over port number, command, cwd basename.
- `Service/PortScanner.swift`: runs both lsof calls via `ToolRunner.run` with a 5 s timeout, off
  main. `kill(pid:)` sends SIGTERM to the process group, SIGKILL after 3 s if still alive.
- `Service/PortsSession.swift`: `@MainActor @Observable`, holds the last scan, `refresh()`,
  `isScanning`. Owned by `AppCore`.
- `UI/PortsScreen.swift` + `PortsView.swift` + `PortsCoordinator.swift`: rows "`:3011`
  node · sxcl-frontend-app". ↵ opens `http://localhost:<port>` in the default browser.
  ⌘K menu: Open in browser, Kill process (confirm dialog, tone `.danger`), Copy port, Copy pid,
  Reveal working directory in Finder, Open in Ghostty. `⌃X` maps to Kill via `perform(_:at:)`.
- Entry: `CommandID.ports` ("Listening Ports") so it gets a hotkey for free, dispatched from
  `LauncherCoordinator.runCommand` to `portsCoordinator.show()`.
- Settings: none beyond the standard enable toggle in the Commands pane.
- Harness: `Tests/ports-test.swift` over `Model/*` with captured lsof fixtures (v4/v6 double,
  zero results exit 1, cwd with spaces).

Shared touch points: `PaletteMode`, `RootPaletteView`, `CommandID`, `AppCore`, `run-tests.sh`.

## Phase 3: Repos (Worktree Repo Jumper) and Dev Server Launcher

One feature, two surfaces. The repo index is the thing both need.

Folder `Features/Repos/`:

- `Model/Repository.swift`: `struct Repository { id (path), name, path, remoteURL?, org?,
  branch?, isDirty?, isWorktree, parentRepoPath?, packageManager?, devScript? }`.
- `Model/RepoIndexBuilder.swift`: pure. Given root directories and an injected directory lister,
  returns repositories. A directory is a repo if it has `.git` (dir or file). Worktrees come from
  parsing `.git/worktrees/*/gitdir` files, which avoids shelling out per repo. Skip names in an
  ignore list (`node_modules`, `*-backup-*`, `patchdeck-worktree-backups`).
- `Model/RemoteURLParser.swift`: pure. `git@github.com:org/repo.git` and `https://…` → web URL
  and org. Read from `.git/config` text, injected.
- `Model/DevCommandDetector.swift`: pure. Lockfile → package manager (`pnpm-lock.yaml`,
  `yarn.lock`, `package-lock.json`, `bun.lock`), `package.json` scripts → prefer `dev`, then
  `start`. Swift packages → `swift run`. Python with `manage.py` → `python manage.py runserver`.
  Returns a command string or nil.
- `Model/RepoQuery.swift`: ranking that favours repo name, then branch, then org.
- `Service/RepoIndex.swift`: `@MainActor @Observable`. Scans roots off main via `Task.detached`,
  caches the result as JSON in `AppPaths.caches()/repos.json`, rescans when the palette opens if
  the cache is older than 10 min. Branch and dirty status are fetched lazily for visible rows
  with `git -C <path> status --porcelain -b` (2 s timeout) and memoised per show.
- `Service/RepoOpener.swift`: the effects. Open in Supacode (try the CLI path
  `/Applications/supacode.app/Contents/Resources/bin/supacode repo open <path>`, fall back to
  `supacode://` deeplink; verify exact CLI syntax first with `supacode repo open --help`).
  Open in Ghostty (`open -na Ghostty --args --working-directory=<path>`). Open in Finder.
  Open on GitHub. Copy path. Start dev server (below).
- `UI/ReposScreen.swift` + `ReposCoordinator.swift`: a `PaletteMode.repos` list with sections
  by root (Talix, SXCL, Olive, Repo). Subtitle: `org/name · branch` with a dot when dirty.
  Worktrees nest under their parent with an indent glyph. ↵ = the default action
  (configurable: Supacode or Ghostty). ⌘K: all actions above.
- Settings pane `Settings/ReposSettingsView.swift`: root directories list (defaults to the five
  found), default open action, ignore patterns, "show worktrees" toggle.
- Entry: `CommandID.repos` ("Repositories") with a hotkey. Also a launcher root-search
  section? No. Keep repos behind the command so upstream launcher ranking stays untouched.

Dev server launcher, inside the same feature:

- Action "Start dev server" on a repo row. Runs `DevCommandDetector`'s command in a new Ghostty
  window in that directory: `open -na Ghostty --args --working-directory=<path> -e <cmd>`.
  Verify Ghostty accepts `-e` this way; if not, write a temp script and pass it as the command.
  Fallback when Ghostty is missing: `ShellCommandRunner.stream` into Tinycast's output window.
- No port bookkeeping. The Ports screen already discovers whatever came up.
- Harness: `Tests/repos-test.swift` over `Model/*` with a fixture tree (regular repo, repo
  with two worktrees, non-repo dir, a `.git` file pointing at a worktree gitdir).

## Phase 4: Talix time tracker

The highest value one and the first networked one. Talk to the MCP endpoint directly; do not go
through `MCPCoordinator`, which is chat-bound by design.

Folder `Features/Talix/`:

- `Model/TalixProject.swift`, `Model/TalixTimeEntry.swift`: plain Codable mirrors of the MCP
  tool inputs and outputs. Entry rule from the server: `date == startTime.prefix(10)` and
  `endTime > startTime`, `startTime`/`endTime` are ISO 8601 with offset.
- `Model/TalixTimer.swift`: pure running-timer state `{ projectId, projectName, description,
  startedAt }`, with `entry(endingAt:rate:calendar:timeZone:)` producing a `TalixTimeEntry`.
  Rounding policy (none, 6 min, 15 min) is a parameter.
- `Model/TalixEntryDraft.swift`: pure. Turns "1.5", "1h30", "90m", "9-11" plus a date word
  (today, yesterday, mon) into start and end. Harness-tested heavily, this is the part that
  will be wrong first.
- `Model/TalixRPC.swift`: pure JSON-RPC request builders for `tools/call` with the five tool
  names, reusing `MCPProtocol` encoders if they are importable without AppKit (they are in
  `Features/MCP/Model/`, Foundation only). Otherwise a 40-line copy.
- `Service/TalixClient.swift`: private ephemeral `URLSession`, `POST` per call, bearer from
  `KeychainSecretStore` under key `talix.apiKey`, `Mcp-Session-Id` handling copied from
  `MCPHTTPTransport`. 15 s timeout. Never logs the key.
- `Service/TalixStore.swift`: `@MainActor @Observable`. Projects cached in Caches (refetch
  daily, copy `CurrencyRateStore`), the running timer persisted in Application Support
  (`talix-timer.json`, it is authored state and must survive a crash), today's entries fetched
  on show.
- `UI/TalixCoordinator.swift`, `TalixScreen.swift`: `PaletteMode.talix` list screen showing
  the running timer card at index 0 (elapsed, project, Stop and Discard actions), then today's
  entries with total hours, then a "Log time" row.
- Commands (all `CommandID` cases, so hotkeys are free): `talixStartTimer` (opens a project
  picker screen, ↵ starts), `talixStopTimer` (asks for a description via the snippet-arguments
  dialog shape, creates the entry, shows a success HUD "Logged 1h 20m to SXCL"),
  `talixLogTime` (opens the Talix screen with an argument strip: Project options, Duration,
  Description), `talixToday` (opens the screen).
- Rate: `create_time_entry` requires `rate`. Verify whether `list_projects` returns a default
  rate per project. If it does, use it. If not, a per-project rate map in settings, with the
  screen refusing to log until a rate exists.
- Billable defaults to true, overridable per project in settings.
- Menu bar: optional later. `TinycastApp` declares `MenuBarExtra` scenes by preference, and a
  third one showing the elapsed timer follows the calendar item's pattern.
- Settings pane: API key field (Keychain), environment (prod or dev URL), rounding, default
  billable, per-project rates.
- Harness: `Tests/talix-test.swift` over `Model/*`: draft parsing, timer to entry, request
  encoding against fixtures, response decoding against a captured `list_projects` payload.
- Verification: log one 1 minute entry to a scratch project on `apidev.talix.app` first, then
  prod.

## Phase 5: Inbox (PRs now, Jira when creds exist)

Folder `Features/Inbox/`:

- `Model/InboxItem.swift`: `{ id, source (.github/.jira), title, subtitle, url, repoOrProject,
  state, updatedAt, needsAction }`.
- `Model/GitHubSearchDecoder.swift`: pure decoding of `gh search prs --json` output.
- `Model/JiraSearchDecoder.swift`: pure decoding of the Jira `search` REST response.
- `Service/GitHubInboxSource.swift`: runs `gh search prs --review-requested=@me --state=open
  --json …`, `gh search prs --author=@me --state=open --json …`, and `gh api notifications`
  for new comments. Located via `ExecutableLocator` so nvm and Homebrew paths resolve.
  No token handling, `gh` owns auth. 10 s timeout.
- `Service/JiraInboxSource.swift`: `GET /rest/api/3/search?jql=assignee=currentUser() AND
  resolution=Unresolved ORDER BY updated DESC` with basic auth (email + API token) from
  `KeychainSecretStore`. Ships disabled until site URL, email, and token are entered.
- `Service/InboxStore.swift`: `CurrencyRateStore` shape, 5 min refresh while the app runs,
  immediate refresh on show, cached in Caches.
- `UI/InboxScreen.swift`, `InboxCoordinator.swift`: `PaletteMode.inbox`, sections "Needs my
  review", "My PRs", "Jira". ↵ opens in Zen. ⌘K: Open, Copy URL, Copy branch name, Checkout in
  repo (only when the Repos index knows the repo: `git -C <path> fetch && gh pr checkout <n>`),
  Open in Supacode (same lookup), Mark read.
- `CommandID.inbox` plus a menu bar badge count is optional later.
- Settings: orgs to include (default the four), Jira site/email/token, refresh interval.
- Harness: `Tests/inbox-test.swift` over `Model/*` with captured `gh` JSON and a Jira fixture.

## Phase 6: ClipShare upload

Folder `Features/ClipShare/`:

- `Model/ClipShareUploadPlan.swift`: pure. Given file size and `partSizeBytes`, the part ranges.
  Given a directory listing, the newest screen recording or screenshot.
- `Model/ClipShareModels.swift`: Codable request and response shapes from
  `clipshare/docs/api.md`.
- `Service/ClipShareClient.swift`: create → put parts → complete, resumable via
  `GET /api/videos/{id}` `uploadedParts`. Bearer from `KeychainSecretStore` `clipshare.token`.
  Private ephemeral session, background-priority `Task.detached`, progress reported through
  `core.showProgress`.
- `UI/ClipShareCoordinator.swift`: commands `clipShareLatest` ("Share latest recording":
  newest `.mov`/`.mp4` in the screenshot directory from
  `defaults read com.apple.screencapture location`, falling back to `~/Desktop`),
  `clipShareClipboard` ("Share file on clipboard"), `clipShareRecent` (a list screen of the
  last 20 uploads from `GET /api/videos`, ↵ copies the share URL, ⌘K: revoke, delete, open).
  On success the share URL goes to the clipboard and a HUD says so.
- Open questions to settle before coding: whether the worker and viewer accept a PNG (the
  pipeline is video-shaped, `MediaPipeline.swift` may transcode `.mov` to MP4 before upload,
  which would mean either shelling out to `ffmpeg` or limiting the launcher path to files
  already MP4). Decide by reading `mac/Sources/ClipShareCore/Media/MediaPipeline.swift`. If
  images need worker changes, that is a separate clipshare task, not part of this fork.
- Token: paste it once in Settings. Reading ClipShare.app's Keychain item from another app is
  not worth the entitlement fight.
- Harness: `Tests/clipshare-test.swift` over `Model/*`.

## Phase 7: Transcript hooks (LocalFlow, Scribe)

What is possible today without touching those apps:

- `CommandID.dictationHistoryToday`: open today's Markdown file.
- `CommandID.pasteLastDictation`: parse today's history file, take the last entry, paste through
  `Paster` (the existing paste effect). Pure `Model/DictationHistoryParser.swift` once the file
  format is confirmed from a real file.
- `PaletteMode.dictationHistory`: a list of entries across days, fuzzy searchable, ↵ pastes,
  ⌘K copies. Reads `~/Library/Application Support/LocalFlow/History/*.md`.
- `PaletteMode.scribeRecordings`: list from `~/Library/Application Support/Scribe/library/*/
  document.json` (title, date, duration), ↵ copies the transcript text, ⌘K reveals the folder.
  Pure `Model/ScribeDocumentDecoder.swift` once one `document.json` has been inspected.

What needs a change in another repo (do only if wanted, and as its own task in `localflow`):

- Add a `localflow://toggle` and `localflow://start` URL scheme to LocalFlow, or a
  `DistributedNotificationCenter` name it listens for. Then Tinycast gets
  `CommandID.toggleDictation`. Scribe cannot get this until its source is restored.

Folder `Features/Transcripts/` for all of the above.

## Phase 8: Screenshot cleanup

Covered by Phase 1 custom commands. A Swift feature is only warranted if you want the run's
result (files trashed and moved) rendered as a HUD. If so: read the LaunchAgent's log tail
after `launchctl kickstart`, pure parser in `Model/`, one `CommandID`. Ten lines of real logic,
so do it last or not at all.

## Cross-cutting decisions

- **Where secrets go.** Talix key, ClipShare token, Jira token: `KeychainSecretStore`, one item
  each, excluded from settings backups like `mcpServers`. Never in `UserDefaults`, never in the
  repo.
- **Where caches go.** Repo index, project lists, inbox snapshots: `AppPaths.caches()`. The
  running Talix timer: `AppPaths.applicationSupport()`.
- **Where shell binaries come from.** `gh`, `supacode`, `git`, `lsof`, `osascript`: resolve
  through `ExecutableLocator` once, never assume PATH inside the app.
- **Screens, not launcher sections.** Every new list is a `PaletteMode` behind a `CommandID`.
  This keeps upstream's launcher ranking and `AppIndex` untouched by us except for nothing at
  all, which is the biggest merge-conflict saver available. Only revisit if a list needs to
  appear in root search.
- **One harness per feature** over `Model/*`, added to `run-tests.sh` and the table in
  `docs/testing.md`.
- **One doc per feature** in `docs/features/<name>.md` opening with `## Invariants`, matching
  upstream's convention.
- **Naming.** Suffixes follow `docs/standards.md#naming`: `Store` for observable persisted
  state, `Client` for a remote API, `Scanner`/`Index` for discovery, `Coordinator` for the
  feature's actions.

## Order and rough size

| Phase | Feature | New Swift files | Shared files touched | Size |
| --- | --- | --- | --- | --- |
| 0 | Setup | 0 | 0 | 1 hour |
| 1 | Quicklinks + custom commands | 0 | 0 | 1 hour |
| 2 | Ports | ~7 | 5 | small |
| 3 | Repos + dev launcher | ~12 | 6 | medium |
| 4 | Talix | ~12 | 6 | medium, plus API verification |
| 5 | Inbox | ~9 | 6 | medium; Jira half blocked on creds |
| 6 | ClipShare | ~6 | 4 | small, blocked on the image question |
| 7 | Transcripts | ~7 | 5 | small; dictation toggle needs a LocalFlow change |
| 8 | Screenshot cleanup HUD | ~3 | 2 | tiny, optional |

Each phase is one feature branch, one PR into the fork's `main`, and each ends with the full
definition of done from `docs/testing.md`.

## Resolved on 2026-09-18

- Supacode: `supacode repo open <absolute path> [--timeout n]`. No `-r` needed.
- Ghostty: `-e <command>` runs a command, and `--working-directory=<path>` is a plain config
  flag. So `open -na Ghostty --args --working-directory=<path> -e <cmd>` is the shape.
- LocalFlow history: Markdown, `# Dictations YYYY-MM-DD`, then one `## HH:MM:SS` heading per
  dictation followed by its text. Parser is trivial.
- Scribe `document.json` keys: `id, title, createdAt, duration, kind, status, modelUsed,
  originalFilePath, segments[], speakers[], knownSpeakers[], tracks[]`. Transcript text comes
  from `segments`.
- ClipShare is video only. The worker stores `video/mp4`, and the Mac app runs every file
  through AVFoundation (passthrough export for compatible MP4/MOV, transcode preset otherwise)
  before upload. The launcher path must copy that export step from
  `mac/Sources/ClipShareCore/Media/MediaPipeline.swift`, and screenshots are out of scope
  unless the worker grows an image route (a separate clipshare task).

## Still to verify before their phase starts

- Talix: does `list_projects` return a rate? Does the dev endpoint accept a `tlx_` key for a
  scratch project?
- Jira: site URL, and whether to use an API token or the Atlassian MCP OAuth.
