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

A read-only scan of the five default roots found 104 repositories, including 18 worktrees, in 184 ms.
This is one local measurement, not a performance guarantee.
