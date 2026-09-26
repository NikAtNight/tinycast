# Spec: app-aware templates

Status: draft, 2026-09-26. Checked against `main` after the upstream merge (`7eb8e72`).

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

### 2. Templates screen filtered to the current app (v1)

A new command, **Templates for This App**, that opens the Snippets screen filtered to
`previousApp`'s templates plus untagged ones in the "AI prompts" group. It's a `CommandID`, so it can
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

## Actions on a template

The ⌘K menu on a template row, primary first:

| Action | Shortcut | What it does |
| --- | --- | --- |
| Paste to {app} | ↵ | Expand, then `TextInjector.deliver` into `previousApp` (today's snippet behavior) |
| Copy | ⌘C | Expand, then put the text on the clipboard |
| Ask AI | ⌘↵ | Expand, then `QuickAICoordinator.ask(_:)`, which opens Quick AI with it as the prompt |
| Open in AI Chat | ⇧⌘↵ | Same as above, but in the AI Chat window |
| Copy raw | ⌥⌘C | The template text with its tokens still in it |
| Edit / Duplicate / Show in Finder | | Same as the snippet screen today |

Ask AI is where AI prompts beat plain snippets. You don't have to be in a chat app to use them.
Pick "Explain this error", it fills `{clipboard}`, and the answer comes back in Tinycast.

## Filling in placeholders

Snippet arguments open a modal dialog today (`DialogController.fillSnippetArguments`). From the
palette, I'd rather reuse the search-field form we just built for quicklinks
(`QuicklinkArgumentSession` and `QuicklinkArgumentsScreen`): a chip naming the template, one argument
at a time in the search field, ↵ to go to the next one. Keyword expansion (typing `;rv` in another
app) keeps the dialog, since the palette isn't open then.

Doing this means lifting the session out of `Quicklinks/` so snippets can use it too. That's the one
refactor this spec needs, and it has a real second user, so it's justified.

## Starter templates

A **Add starter AI prompts** button in Settings > Snippets that writes about ten `.md` files into the
snippets folder, in the "AI prompts" group. Some are tagged for Claude, Cursor and ChatGPT, and some
are untagged. For example: Explain this code, Review this diff, Write tests for, Summarize,
Rewrite shorter, Turn into a ticket, Debug this error.

- Nothing gets seeded silently on upgrade. The button is the only way in, so there's no migration.
- They're written as normal files, so once added they're mine to edit or delete.
- It skips any name that already exists, so pressing it twice doesn't create duplicates.
- The pack ships as `.md` files in the app's resources, in the same format the user edits.

## Invariants

- `apps` and `group` travel in settings backups with the snippet files. They grant nothing.
- `snippetsEnabled` stays excluded from backups. Pasting still requires Snippets to be on and
  Accessibility granted, same as now.
- The menu bar indicator flag (v2) can be backed up. Watching app switches isn't a TCC capability.
- The caret still decides where text goes (`InjectionTarget`). `apps` only decides what gets
  *offered*.
- Everything under `Snippets/Model/` stays Foundation-only.

## Work breakdown

1. `apps` and `group` in `Snippet` and the serializer, with `snippets-test` cases. Editor fields.
2. The "For {app}" section in `AppIndex.orderedResults` and `LauncherList`, plus harness cases in
   `recents-test` or a new one.
3. `CommandID.templatesForThisApp` and the filtered snippet screen.
4. Copy, Ask AI and Open in AI Chat actions on snippet rows.
5. Move the argument session out of Quicklinks and use it for snippets opened from the palette.
6. The starter pack and its Settings button.
7. (v2) Menu bar indicator.

Each step ships on its own. Steps 1 to 4 are the useful core. Docs go in `docs/features/snippets.md`
and `docs/features/launcher.md` in the same commits.

## Open questions

- **Browsers.** ChatGPT and Claude in Safari or Arc look like "Safari" to `previousApp`. Matching on
  the page URL means AppleScript per browser plus an Automation prompt. Worth it, or tag the browser
  and move on?
- **Naming.** Keep calling them Snippets in the UI, or rename the pane to "Snippets & Templates"?
- **ChatGPT desktop bundle ID.** It isn't installed here, so `com.openai.chat` needs checking before
  it goes in the starter pack.
- **Per-app default.** Should an app get one "default" template that ↵ on the indicator pastes
  straight away, or is a short list always better?
