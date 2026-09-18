## Invariants

- Repositories live behind `CommandID.repos` and `PaletteMode.repos`. They add no launcher category.
- `AppCore` owns `RepoIndex` and `ReposCoordinator`. Settings injects the coordinator through
  `@Environment`; palette actions receive it from the core. No scan runs during startup.
- Every model takes its filesystem inputs as parameters. Discovery reads Git metadata and never runs
  Git. The service performs filesystem work in a detached task.
- Scan roots and ignore patterns form the cache key. A changed policy cannot publish an older scan.
  An empty roots list scans nothing.
- Git status runs only for visible rows, at most four calls at once. Each call uses a two-second
  `ToolRunner` timeout. Results are memoized for one showing of the screen.
- Paths are process arguments or URL query items. Project script contents never become launcher shell
  text. Dev commands select fixed script names, `dev` before `start`.
- Caches use `AppPaths.caches()/repos.json`, isolated by app bundle ID. No secrets are stored.

## Invocation and discovery

Phase 3 of [the fork plan](../fork-plan.md) defines this feature. The Repos coordinator owns its flow.
The Repositories command opens the palette list. Return opens the selected directory in Supacode or
Ghostty, as configured in Settings. Command-K offers Supacode, Ghostty, Finder, remote URL, copy path,
dev server and refresh actions. Command-Return reveals the directory; Control-Command-C copies its path.

`RepoIndexBuilder.build` walks visible directories under the configured roots, stopping at a repository.
It recognizes `.git` directories and files. It resolves relative `gitdir` and `commondir` paths, then reads
`worktrees/*/gitdir` once per common Git directory to discover linked worktrees, including those outside
scan roots. Missing worktree paths are skipped. Paths are deduplicated; directory symlinks are not
followed. Root sections contain parent repositories followed by their worktrees.

Defaults are `~/Talix`, `~/SXCL`, `~/Olive`, `~/Repo` and `~/gateway`. Ignore patterns initially contain
`node_modules`, `*-backup-*` and `patchdeck-worktree-backups`. Matching reuses `FileSearchIgnoreList`.
Settings can add or remove roots and patterns, choose the Return action, and hide worktrees.

Opening the screen uses a matching cache younger than ten minutes or scans again. Refresh forces a scan.
`RemoteURLParser` reads the origin remote and normalizes SSH and web forms, removing credentials.
`RepoQuery` reuses `FuzzyMatch`, favoring name, then known branch, then organization. Branch searches
cover status already fetched in this session; Tinycast does not launch Git for every search candidate.

Visible rows run `git --no-optional-locks -C <path> status --porcelain -b`. The subtitle shows the known
branch, and a dot marks uncommitted changes. Failed status calls leave dirty status unknown and retain the last known branch. Hiding the palette,
leaving the screen or refreshing invalidates the status memo. Late results cannot update a later show.
Unreadable roots produce a warning while readable roots remain usable. Cache write failures also report
through the HUD; the in-memory index still works.

## Opening and dev servers

`RepoOpener` calls Supacode's installed CLI with `repo open <absolute path> --timeout 10`. If that binary
and a located CLI are absent, it opens `supacode://repo/open?path=<encoded path>`. Supacode's installed
help and bundled deeplink reference confirm both forms. CLI errors reach Tinycast's failure dialog.

Ghostty opens as a new application instance with `--working-directory=<path>`. Starting a dev server
adds `-e <command>`. `DevCommandDetector` chooses pnpm, yarn, npm or bun by lockfile and selects `dev`,
then `start`. A Swift package uses `swift run`; Django's `manage.py` uses `python manage.py runserver`.
An unsupported project has no dev-server action.

When Ghostty is absent, `ShellCommandRunner.stream` runs the command in that directory and streams to
`CommandOutputPresenter`. Only one fallback server runs at a time. Its output window can stop it or run
it again. Ghostty owns processes launched in its windows. Repos does not track ports or kill servers
launched there.

## Verification

`Tests/repos-test.swift` builds a UUID temporary fixture tree and compiles the shipped models. It covers
regular repositories, two linked worktrees, a non-repository, relative `.git` files, stale metadata,
overlapping roots, ignore rules, pnpm, bun, Swift, Django, remote credentials, query ranking and JSON.
Run `./Scripts/run-tests.sh repos-test`.

Local verification on 2026-09-18 used macOS 27 and Xcode 27. The focused harness passed. A read-only scan
of the five default roots found 104 repositories, including 18 worktrees, in 184 ms. This is one local
measurement, not a performance guarantee.

The standard Debug build was blocked by Icon Studio export. A build excluding `tinycast.icon` and
passing `-Xfrontend -disable-sandbox` succeeded with the two existing Clipboard warnings and an
AppIntents metadata notice. These overrides are verification commands only, not project settings.
Launch Services refused both Ghostty and the Debug app with `kLSNoExecutableErr`; a direct Debug process
also exited with signal 6. Live UI and dev-server acceptance remain unverified.

Evidence logs are local under `.derived/repos-*.log`. Before integration, verify that Return uses the
configured app, worktree rows open their own directory, scrolling loads status without moving selection,
Command-K starts a server in the selected directory, and the fallback output window can stop and rerun
its process. Test hide and reopen, root changes, a missing root and a cache older than ten minutes.

### Current integration gaps

Two edits await permission because they fall outside this task's shared-file allowlist:
`CommandCatalog.swift` must add `.repos: [.repos]` to `SettingsTab.ownedCommands`, and
`SettingsBackupCoverage.swift` must classify the four repository preferences. Until then the command
appears in Commands rather than the Repositories command section, follows Enable Commands, and
`settings-backup-test` fails for those four keys. The concrete patch is `.derived/repos-integration.patch`.
It has not been applied.

The sandbox also refuses staging because the worktree index lives outside its writable roots at
`/Users/nikhlkapadia/Talix/tinycast/.git/worktrees/repos/index.lock`. No commit was created and nothing
was pushed. These scope and sandbox blockers belong to the integrating owner.

### Executed checks

All commands ran from this worktree unless marked HEAD baseline. `.derived` contains only local evidence
and is not part of the feature. The project was regenerated with `xcodegen generate` from unchanged
`project.yml`, because its checked-in project uses explicit source references.

| Command | Result |
| --- | --- |
| `xcodegen generate` | PASS, registers the ten new Swift files |
| `swiftc -swift-version 6 Tinycast/Features/Repos/Model/*.swift Tinycast/Features/FileSearch/Model/FileSearchIgnoreList.swift Tinycast/Features/Launcher/Model/SearchRelevance.swift Tests/repos-test.swift -o /tmp/repos-test-models`, then `/tmp/repos-test-models` | PASS |
| `TMPDIR="$PWD/.derived/test-tmp/" ./Scripts/run-tests.sh repos-test` | BLOCKED, sandbox denies CPU-count lookup and leaves xargs concurrency empty |
| `TINYCAST_TEST_JOBS=2 TMPDIR="$PWD/.derived/test-tmp/" ./Scripts/run-tests.sh repos-test` | PASS, including final fixture assertions |
| `TINYCAST_TEST_JOBS=2 TMPDIR="$PWD/.derived/test-tmp/" ./Scripts/run-tests.sh` | FAIL, 39 of 77 harnesses, mostly compiler macro sandbox failures |
| `PATH="$PWD/.derived/test-bin:$PATH" TINYCAST_TEST_JOBS=2 TMPDIR="$PWD/.derived/test-tmp/" ./Scripts/run-tests.sh` | FAIL, 9 of 77 harnesses; wrapper adds `-Xfrontend -disable-sandbox` to swiftc |
| `./Scripts/run-tests.sh <name>` on archived HEAD with the same compiler wrapper | All eight non-backup failures reproduced exactly: file-search, clipboard, clipboard-text, pasteboard, custom-command, snippets, notes and notes-editor |
| `./Scripts/lint.sh` | PASS, no Repos warnings; existing unrelated warnings remain |
| `grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Tinycast/Features/*/Model/` | PASS, empty output |
| `git diff --check` | PASS |
| `git apply --check .derived/repos-integration.patch` | PASS, patch remains unapplied |
| `/Applications/supacode.app/Contents/Resources/bin/supacode repo open --help` | PASS, CLI syntax confirmed |
| `/Applications/Ghostty.app/Contents/MacOS/ghostty +help` | PASS, argument syntax confirmed |
| `open -na Ghostty --args --working-directory=<UUID temp directory> -e <marker command>` | FAIL, application lookup failed |
| Same Ghostty command with `/Applications/Ghostty.app` | FAIL, `kLSNoExecutableErr`; marker never created |
| `open -n ".derived/Build/Products/Debug/Tinycast Dev.app"` | FAIL, `kLSNoExecutableErr` |
| Direct Debug executable through Python `subprocess.Popen`, observed for three seconds | FAIL, exited with signal 6; no process left running |
| `git add Tinycast/Features/Repos/Model Tests/repos-test.swift` | BLOCKED, cannot create the worktree index lock |

The normal build command was:

```sh
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath .derived build
```

It failed during icon export. The same command with
`EXCLUDED_SOURCE_FILE_NAMES=tinycast.icon ASSETCATALOG_COMPILER_APPICON_NAME=` reached Swift compilation
but failed to start macro plugins. Adding
`'OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -disable-sandbox'` passed after fixing one optional-return
inference error in `RepoOpener`. The final build with both temporary overrides also passed. This does
not establish that the standard build or the UI smoke test passes outside the sandbox.
