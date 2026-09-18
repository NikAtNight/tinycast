## Invariants

- Talix owns no launcher section. Four `CommandID` cases open or act on `PaletteMode.talix`.
- `AppCore` owns `TalixStore` and `TalixCoordinator`. Views call the coordinator through the environment.
- Models import Foundation only. Parsing takes the clock, calendar and timezone as arguments.
- The API key lives in the bundle-scoped `KeychainSecretStore` service `talix.apiKey`, under one fixed
  UUID account because the shared store accepts UUID accounts. It never enters defaults or backups.
- HTTP uses a private ephemeral session with no URL cache, a 15-second timeout, bearer authorization,
  and no Origin header. Talix does not use the chat-bound MCP coordinator.
- A timer belongs to the environment where it started. Its rate and billable value are captured at
  start. Switching environments cannot redirect it into another project.
- Missing rates block logging. A supplied project rate wins; otherwise Settings must hold an explicit
  rate for that environment and project. Zero is allowed, but never assumed.
- The timer is authored state in Application Support. Projects are disposable data in Caches.
- The final confirmation names the environment, project, interval, rate and billing choice. Cancel
  before submission leaves a running timer unchanged. Once a write is attempted, retries retain the
  exact interval, including after a crash.

## Commands and screen

`talixStartTimer` opens a project picker. Return starts the selected project after checking its rate.
A second timer is refused. `talixStopTimer` asks for a description using the existing snippet-argument
accessory, then shows the entry confirmation. The existing accessory's first button reads Expand.
The confirmation's action reads Log Time.

`talixToday` shows the timer card first, followed by today's entries and a Log time row. The total
includes all fetched entries, including non-billable entries. The timer has Stop and Log and Discard
buttons; its action menu also offers both. Discard asks first and makes no API write.

`talixLogTime` selects the Log time row. Its argument strip contains project choices, duration and
description. Project choices include the client or ID so duplicate names remain distinguishable.
The row reuses the quicklink argument controls and palette-owned options menu. Failed submissions
retain the typed draft and interval in memory; closing the app loses an unsubmitted manual draft.

## Parsing

`TalixEntryDraft.parse` accepts decimal hours such as `1.5`, hours and minutes such as `1h30` or
`1h30m`, minutes such as `90m`, and 24-hour clock ranges such as `9-11` or `9:15-11:45`.
Append `today`, `yesterday`, an English weekday name, or its three-letter abbreviation.
A weekday means the most recent matching day, including today.

Durations end at the current local clock time on the selected day. Their start may fall on the
previous day. Clock ranges stay within the selected day; reversed and overnight ranges are refused.
Durations must be positive and at most 24 hours. Spring-forward clock times that do not exist are
refused; repeated fall-back clock times use the first occurrence. Elapsed time uses actual seconds.

Rounding is none, up to six minutes, or up to fifteen minutes. It rounds elapsed duration upward.
Timers and clock ranges retain their start; duration-only drafts retain their end. Writes derive the
entry date from the formatted start timestamp, preserving its timezone offset.

## Contract and storage

The contract was checked against the local Talix backend `src/mcp/server.ts`. Its current project
response contains no rate. The decoder also accepts an optional numeric or decimal-string rate.
Time entries decode decimal strings, millisecond timestamps and legacy entries with null timestamps.
Legacy totals use the server's duration in hours. Invalid numeric durations are refused.

`TalixRPC` uses `MCPProtocol` for all five tool request builders. Write fields are flat beside
`projectId`, not nested under `entry`. Read results come from MCP text content; structured content is
also accepted. RPC errors, tool errors, malformed payloads and mismatched response IDs fail explicitly.
`TalixClient` supports JSON and SSE replies, replays session IDs, and paginates time entries per project.
The current server is stateless and accepts direct tool calls without an initialization handshake.

`TalixStore.refresh` loads an environment-tagged project cache, refetches projects when it is older
than a day, and fetches today's entries on each show. Refresh failures remain visible in the screen.
Changing the key waits for a refresh to finish, removes the cache and drops the HTTP session. Keys
cannot change while a timer exists. Project rates and billable overrides are scoped by environment.

`talix-timer.json` holds the timer, environment, billing values and any submitted entry awaiting a
successful response. Atomic writes run off the main actor. A corrupt file is preserved and blocks new
timers so recovery never silently overwrites authored state. Successful logging removes the file.
The backend deduplicates writes by user, project and normalized start/end times. The client never
changes these timestamps when retrying a pending timer submission.

## Verification

The feature owner is the Talix phase of `docs/fork-plan.md`. `Tests/talix-test.swift` compiles the
shipped models, client and store. `Tests/talix-fixtures/server.js` is a loopback-only Node server with
sanitized fixtures. No real API calls or real credentials are used.

The harness covers duration formats, all weekdays, invalid input, local midnight, both DST changes,
rounding, timer billing, date/offset invariants, flat requests for all five tools, decimal and null
response fields, pagination, JSON/SSE replies, session headers, HTTP/RPC/tool errors, missing keys,
retry after a lost response, durable timer recovery and preservation of corrupt timer files.

Run `./Scripts/run-tests.sh talix-test`, then the full suite, Debug build, lint and Model purity check.

## Files in this change

New files under `Tinycast/Features/Talix/`:

- `Model/TalixProject.swift`, `TalixTimeEntry.swift`, `TalixTimer.swift`, `TalixEntryDraft.swift`,
  `TalixRPC.swift`, `TalixEnvironment.swift`.
- `Service/TalixClient.swift`, `TalixStore.swift`.
- `UI/TalixCoordinator.swift`, `TalixScreen.swift`, `TalixList.swift`.
- `Settings/TalixSettingsView.swift`.

Also added `Tests/talix-test.swift`, `Tests/talix-fixtures/projects.json`, `entries.json`, `server.js`,
and this document.

Shared edits are `AppCore.swift`, `CommandID.swift`, `LauncherCoordinator.swift`, `AppSettings.swift`,
`AppSettingsKey.swift`, `SettingsAnchor.swift`, `SettingsDetailView.swift`, `SettingsSearchCatalog.swift`,
`SettingsTab.swift`, `PaletteMode.swift`, `RootPaletteView.swift`, `Scripts/run-tests.sh`,
`docs/testing.md`, and generated `Tinycast.xcodeproj/project.pbxproj`.

The feature introduces concrete model, client, store and coordinator types. It adds no shared
abstraction. It reuses `MCPProtocol`, `SSEParser`, `KeychainSecretStore`, quicklink argument controls,
palette list styling and the existing dialog forwarders.
