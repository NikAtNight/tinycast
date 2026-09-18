## Invariants

- Inbox opens through `CommandID.inbox` and `PaletteMode.inbox`. It adds no launcher section.
- `AppCore` owns `InboxStore` and `InboxCoordinator`. The palette supplies the coordinator to
  `InboxScreen`; list and Settings views read it through `@Environment`.
- GitHub calls are read-only. `gh` owns authentication and `ExecutableLocator` finds its binary.
  Each call has a ten-second timeout through `ToolRunner`.
- Jira stays disabled until a site, email, and token are saved together. All three live in one
  bundle-scoped `KeychainSecretStore` item. They never enter defaults, fixtures, logs, or backups.
- Jira uses a private ephemeral session with no URL cache. Only HTTPS `*.atlassian.net` site
  roots are accepted. No test makes a Jira request.
- Mark read changes only Tinycast. A later update makes the item unread again.
- Models import only Foundation. Decoders receive their data and Jira site as arguments.

## Flow

Phase 5 of [the fork plan](../fork-plan.md#phase-5-inbox-prs-now-jira-when-creds-exist) defines the
scope. Inbox serves the person signed into `gh` and, when configured, the Jira account in Keychain.
The Inbox feature owns this record.

`LauncherCoordinator.runCommand(.inbox)` calls `InboxCoordinator.show()`. `RootPaletteView`
creates `InboxScreen`, which requests a refresh on entry and whenever the palette becomes visible. The store also refreshes at startup
and every five minutes while the app runs. Settings accepts intervals from one to sixty minutes.
Only one refresh runs at a time. Reopening during a refresh uses the request already in progress.

GitHub runs two open-PR searches, with review-requested and author set to `@me`. Repeated `--owner`
flags restrict results to the configured owners. The defaults are NikAtNight, dev-talix,
ServiceXcelerator, and olivehq. An empty list fetches nothing. Each search requests up to GitHub's
1,000-result search limit, newest first.

The paginated unread notification feed marks matching PRs as needing attention and advances their
update timestamp for new comments. Notifications for issues or PRs outside the two searches add
no rows. A PR present in both searches appears once in Needs my review.

The list groups rows into Needs my review, My PRs, and Jira. Empty groups have no header. Search
matches every typed term against title, repository or project, and subtitle. Within a group,
newest updates come first. A click selects, a double click or Return opens, and right click or
Command-K opens actions. Command-Return copies the URL.

| Action | Effect |
| --- | --- |
| Open | `NSWorkspace` opens the web URL in the system default browser. |
| Copy URL | `Paster` copies the web URL and shows a HUD. |
| Copy branch name | GitHub rows only. `gh pr view --json headRefName` fetches the branch on demand. |
| Mark read | Persists the item's current update timestamp locally. |
| Refresh | Requests a refresh without clearing existing rows. |

Checkout in repo and Open in Supacode are deferred until the Repos index is available.

## Storage and failures

`InboxStore` follows `CurrencyRateStore`'s refresh-loop and snapshot shape. IO and decoding run in
nonisolated service functions and detached tasks. `Caches/<bundle-id>/inbox.json` stores the
refetchable rows. `Application Support/<bundle-id>/inbox-preferences.json` stores owners, interval,
local read markers, and a cache-scope identifier. These machine-local preferences stay outside
Tinycast's settings backup. The command's visibility and hotkey use the existing Commands pane.

Changing owners or the Jira connection changes the cache scope and removes rows from that source.
A result started under the old scope cannot publish into the new one. Preference writes are
serialized. Read markers survive relaunch and cache eviction.

A failed source preserves its previous rows while the other source can update. An inline error
and Retry button remain visible, including when there are no rows. Action and save failures use
the standard HUD. A missing `gh` explains how to install and authenticate it. Startup resolves
`gh` once, so installing it while Tinycast runs requires restarting Tinycast.

## Jira contract

The implementation uses the current [Jira Cloud issue search API](https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issue-search/),
`GET /rest/api/3/search/jql`. The plan's older `/search` endpoint is being removed. The query is
`assignee=currentUser() AND resolution=Unresolved ORDER BY updated DESC`. It requests summary,
status, updated, and project fields and follows `nextPageToken` until `isLast` is true. A missing
or repeated continuation token fails the refresh. Jira browser links use the configured site and
`/browse/<issue-key>`.

GitHub's [search JSON fields](https://cli.github.com/manual/gh_search_prs) omit branch names, which
is why [PR view](https://cli.github.com/manual/gh_pr_view) runs only for Copy branch name.
Notifications use [`gh api --paginate --slurp`](https://cli.github.com/manual/gh_api) so all pages
form one JSON value.

## Verification

`Tests/inbox-test.swift` compiles shipped `Model/*` sources. It checks captured GitHub shapes,
empty review results, review precedence, notification matching, null subject URLs, local read
markers, new activity, Jira date offsets and pagination, invalid payloads, safe GitHub URLs,
search order, owner validation, and snapshot encoding.

Fixtures under `Tests/inbox-fixtures/` came from read-only `gh search prs` and `gh api notifications`
on 2026-09-18. Repository names, IDs, titles, and URLs are replaced with examples; unused notification
fields are omitted. The review query returned an empty array. The nonempty authored fixture also
exercises review decoding. The Jira fixture is handwritten against the documented response.

Jira live verification needs a site, email, and API token.
