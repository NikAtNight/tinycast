# Spec: app-aware templates

Status: v1 built on `feat/templates` (2026-09-26), except step 5. v2 and v3 are not started.
What shipped is documented in [snippets.md](features/snippets.md#snippets-for-an-app).

## What we want

A library of text templates, mostly AI prompts, that I can find in the palette, fill in, and drop
into whatever app I'm in. When I'm in an app that has templates tagged for it (Claude, Cursor,
Slack...), Tinycast shows that and offers them first.

## The main call: build on Snippets, don't add a new feature

Snippets already do most of this:

- One Markdown file per snippet in `~/Library/Application Support/<bundle-id>/Snippets/`, with
  frontmatter (`SnippetMarkdownSerializer`).
- `SnippetTemplateEngine` handles `{argument name= default= options=}`, `{clipboard}`,
  `{selection}`, `{date}`, `{cursor}`, `{snippet:Name}` and modifiers.
- `TextInjector.deliver` pastes into the app behind the palette, with the Accessibility write and
  keystroke fallback already worked out.
- They already show in the launcher (`AppEntry.Kind.snippet`) and have their own screen
  (`PaletteMode.snippets`).

A separate Templates feature would duplicate the store, the file watcher, the engine and the paste
path. AGENTS.md says not to create a parallel implementation, and I agree with it here. So
"templates" are snippets with two new optional fields, plus an app-aware layer on top.

## Data model

Two new optional frontmatter keys on `Snippet`:

```markdown
---
name: "Review this diff"
keyword: ";rv"
apps: ["com.anthropic.claudefordesktop", "com.todesktop.230313mzl4w4u92"]
group: "AI prompts"
---
Review this diff for bugs and missing tests. Be blunt.

{clipboard}

Focus on: {argument name="focus" default="correctness"}
```

- `apps`: bundle IDs the template is meant for. Empty means "anywhere", which is every snippet
  today, so existing files don't change.
- `group`: a free-text label used for a section header and filtering ("AI prompts", "Replies").
  Optional.

Both are parsed by `SnippetMarkdownSerializer` in `Snippets/Model/`, so they stay Foundation-only and
`snippets-test` covers them. The serializer rejects unknown keys today, so an older build reading a
new file would fail. That's fine because we're latest-only, but it means the serializer change and
the harness update land together.

In the editor (`SnippetEditorPanel`), add an app picker (running apps plus "Choose app…") and a group
field.

## Where templates show up

### 1. Palette, for the app I came from (v1)

`PaletteWindowController.show()` already records `previousApp` before the palette opens. When the
query is empty and that app has tagged templates, root search gets a **"For Claude"** section (the
app's name and icon) between Favorites and Recent. Up to five rows, most recently used first.

This needs no new permission and no background work. It uses the same `AppIndex.orderedResults`
path as the Recent section we just merged, with a `forAppCount` next to `recentCount`.

### 2. Snippets screen filtered to the current app (v1)

A new command, **Snippets for This App**, that opens the Snippets screen filtered to
`previousApp`'s tagged templates. It's a `CommandID`, so it can
take a global hotkey (for example ⌥Space in Claude to go straight to prompts).

### 3. Menu bar indicator (v2, off by default)

A small `NSStatusItem` (or a dot on the existing menu bar icon) that lights up when the frontmost
app has tagged templates. Clicking it lists them, and picking one pastes into that app.

This is the first thing in Tinycast that watches the frontmost app continuously. It would observe
`NSWorkspace.didActivateApplicationNotification` (the snippet keyword listener already observes it
for buffer resets). No TCC permission needed. It's off by default because a menu bar item that
flickers on every app switch gets old fast.

### 4. Floating pill next to the text field (not planned)

A little icon near the caret, like Grammarly. It needs Accessibility to find the focused element's
frame, has to follow scrolling and window moves, and fights every app's own UI. I'd skip it unless
v1 and v2 turn out not to be enough.

## Browsers (v3)

Desktop apps come first. In a browser, `previousApp` is just "Safari" or "Arc", so a template tagged
for Claude never shows up on claude.ai. v3 fixes that by matching the page as well as the app.

- **A new `sites` field** next to `apps`, with host names like `["claude.ai", "chatgpt.com"]`. A
  template tagged `apps: [Claude desktop]` and `sites: [claude.ai]` shows up in both places.
- **Reading the front tab's URL** over AppleScript, and only when the palette opens over a known
  browser. Safari uses `URL of front document`. Chrome, Arc, Brave and Edge use
  `URL of active tab of front window`. Firefox has no scripting dictionary, so it's out.
- **Permission.** Tinycast already has the `com.apple.security.automation.apple-events` entitlement
  and `NSAppleEventsUsageDescription`, and Spotify already scripts an app this way
  (`SpotifyPlayer`). So nothing new is needed in the project. Each browser asks once, the first time.
  If I decline, that browser falls back to matching on the app alone.
- **Where it runs.** The URL read is a Service call off the main thread with a short timeout, so a
  hung browser can't stall the palette opening. `Model/` only ever sees the host string.
- **What stays local.** Only the host is kept, never the full URL, and it isn't written anywhere.

The "For Claude" palette section and "Templates for This App" work the same way. They just match on
the page host when there is one.

## Actions on a template

The ⌘K menu on a template row, primary first:

| Action | Shortcut | What it does |
| --- | --- | --- |
| Paste to {app} | ↵ | Expand, then `TextInjector.deliver` into `previousApp` (today's snippet behavior) |
| Copy Snippet | | Expand, then put the text on the clipboard |
| Ask AI | | Expand, then `QuickAICoordinator.ask(_:)`, which opens Quick AI with it as the prompt |
| Edit / Create / Show in Finder | | Same as the snippet screen today |

Built without key bindings: menu items only. "Open in AI Chat" was dropped because Quick AI's ⌘J
already moves the conversation into the AI Chat window. "Copy raw" was dropped as not worth a row.

Ask AI is where AI prompts beat plain snippets. You don't have to be in a chat app to use them.
Pick "Explain this error", it fills `{clipboard}`, and the answer comes back in Tinycast.

## Filling in placeholders

Snippet arguments open a modal dialog today (`DialogController.fillSnippetArguments`). From the
palette, I'd rather reuse the search-field form we just built for quicklinks
(`QuicklinkArgumentSession` and `QuicklinkArgumentsScreen`): a chip naming the template, one argument
at a time in the search field, ↵ to go to the next one. Keyword expansion (typing `;rv` in another
app) keeps the dialog, since the palette isn't open then.

Doing this means lifting the session out of `Quicklinks/` so snippets can use it too. That's the one
refactor this spec needs, and it has a real second user, so it's justified. **Not built yet**:
Copy and Ask AI use the existing argument dialog for now.

## Starter templates

A **Add starter AI prompts** button in Settings > Snippets that writes about ten `.md` files into the
snippets folder, in the "AI prompts" group. Some are tagged for Claude, Cursor and ChatGPT, and some
are untagged. For example: Explain this code, Review this diff, Write tests for, Summarize,
Rewrite shorter, Turn into a ticket, Debug this error.

- Nothing gets seeded silently on upgrade. The button is the only way in, so there's no migration.
- They're written as normal files, so once added they're mine to edit or delete.
- It skips any name that already exists, so pressing it twice doesn't create duplicates.
- The pack is `SnippetStarterPack` in `Snippets/Model/`, so it stays Foundation-only and
  `snippets-test` checks that every prompt round-trips and declares the arguments it means to.

## Invariants

- `apps` and `group` travel in settings backups with the snippet files. They grant nothing.
- `snippetsEnabled` stays excluded from backups. Pasting still requires Snippets to be on and
  Accessibility granted, same as now.
- The menu bar indicator flag (v2) can be backed up. Watching app switches isn't a TCC capability.
- The caret still decides where text goes (`InjectionTarget`). `apps` only decides what gets
  *offered*.
- Everything under `Snippets/Model/` stays Foundation-only.

## Work breakdown

1. Done. `apps` and `group` in `Snippet` and the serializer, with `snippets-test` cases. Editor
   fields.
2. Done. The "For {app}" section in `AppIndex.orderedResults` and `LauncherList`. No harness: the
   ordering lives in `AppIndex`, which the harnesses don't compile.
3. Done. `CommandID.snippetsForThisApp` and the filtered snippet screen.
4. Done. Copy Snippet and Ask AI on snippet rows.
5. Not started. Move the argument session out of Quicklinks and use it for snippets.
6. Done. The starter pack and its Settings button.
7. (v2) Menu bar indicator.
8. (v3) `sites` field, the browser URL reader, and host matching in the palette section.

Each step ships on its own. Steps 1 to 4 are the useful core. Docs go in `docs/features/snippets.md`
and `docs/features/launcher.md` in the same commits.

## Open questions

- **Naming.** Keep calling them Snippets in the UI, or rename the pane to "Snippets & Templates"?
- **ChatGPT desktop bundle ID.** It isn't installed here, so the starter pack tags only Claude and
  Cursor. `com.openai.chat` needs checking before it's added.
- **Per-app default.** Should an app get one "default" template that ↵ on the indicator pastes
  straight away, or is a short list always better?
