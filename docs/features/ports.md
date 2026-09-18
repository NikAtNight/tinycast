## Invariants

- Ports lives behind `CommandID.ports` and `PaletteMode.ports`. It adds no launcher section,
  persisted state, background polling, or settings beyond the standard Commands controls.
- `AppCore` owns `PortsSession` and `PortsCoordinator`. Opening the screen refreshes its snapshot.
  Refreshes never overlap. A request during a scan queues one further scan.
- The model is pure. `LsofParser` receives text, and `PortsQuery` receives rows and a query.
  IPv4 and IPv6 listeners collapse by PID and port, preserving the first address.
- Every lsof call uses `ToolRunner` with a five-second timeout from a detached worker.
  Exit 1 with empty output means no listeners. Other scan failures appear on screen and expose no
  row actions. A missing or inaccessible working directory leaves its row visible without directory actions.
- Kill always asks through `core.confirm` with `.danger`, whether invoked from the menu or ⌃X.
  It stops the entire process group, as the dialog states. Invalid PIDs, PID 1, Tinycast itself,
  and Tinycast's own group are rejected. SIGTERM comes first, then SIGKILL after three seconds if
  the group still exists. No privileges are elevated.

## Entry and actions

Phase 2 of [the fork plan](../fork-plan.md) defines this feature. The Ports coordinator owns the
flow. `LauncherCoordinator.runCommand` opens `PortsScreen` through `PortsCoordinator.show()`.
`PortsSession` resolves lsof with `ExecutableLocator` and retains the executable for later scans.
It publishes listeners enriched with one working-directory lookup per PID.

Rows show the port, command, project directory basename, and PID. Search uses the existing
`FuzzyMatch` scorer over the port, command, and directory basename. Blank input lists every port,
ordered by port then PID. No search history or frecency is recorded.

Return opens `http://localhost:<port>` through `NSWorkspace`. The actions menu offers opening,
copying the port or PID, revealing the directory in Finder, and opening it in a new Ghostty instance.
Ghostty receives the directory as one argument, including spaces. Missing Ghostty reports a HUD.
⌘R refreshes, including from an empty or failed screen. Kill reports its result in a HUD and refreshes.
Cancellation of the confirmation sends no signal.

## Verification

`Tests/ports-test.swift` compiles the shipped model and fuzzy scorer. It checks deduplication,
IPv6 addresses, malformed PIDs and ports, escaped command names, empty results, directory spaces,
and fuzzy queries. The literal fixture was captured using temporary Python IPv4 and IPv6 loopback
listeners sharing a PID and port, in a temporary directory with spaces. The capture used
`lsof -nP -iTCP -sTCP:LISTEN +c0` and `lsof -a -p <pid> -d cwd -Fn`. Closing both sockets produced
exit 1 with empty stdout in a PID-scoped listener query.

Run `./Scripts/run-tests.sh ports-test`. A separate service check exercised a live scan, invalid PID
rejection, SIGTERM termination, and SIGKILL escalation against disposable child process groups.
