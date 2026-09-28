import SwiftUI

/// Search Snippets: the enabled library filtered by the search field, previewed before it pastes.
struct SnippetsScreen: PaletteScreen {
    let store: SnippetsStore
    let core: AppCore
    let vm: PaletteState

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }
    let openActions: () -> Void

    /// The app the list is narrowed to; nil when Search Snippets opened it, or nothing sits behind.
    private var app: PasteTarget? {
        core.snippetCoordinator.showsOnlyAppSnippets ? vm.pasteTarget : nil
    }

    /// A disabled snippet is off everywhere, so the browser lists exactly what the launcher does.
    var rows: [StoredSnippet] {
        var enabled = store.snippets.filter { $0.snippet.isEnabled }
        if core.snippetCoordinator.showsOnlyAppSnippets {
            let bundleID = app?.bundleID
            enabled = enabled.filter { record in bundleID.map(record.snippet.isOffered) ?? false }
        }
        let query = vm.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return enabled }
        return enabled.filter { record in
            record.snippet.name.localizedCaseInsensitiveContains(query)
                || record.snippet.keyword?.localizedCaseInsensitiveContains(query) == true
        }
    }

    let primaryActionTitle = "Paste Snippet"

    private func record(at selection: Int) -> StoredSnippet? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let record = record(at: selection) else { return nil }
        return SnippetActionsMenu.content(record: record, core: core)
    }

    func activate(at selection: Int) {
        guard let record = record(at: selection) else { return }
        core.snippetCoordinator.expandSnippetFromPalette(id: record.id)
    }

    func secondary(at selection: Int) -> Bool { false }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            EmptyResults(text: emptyMessage)
        } else {
            let selected = record(at: selection)
            HStack(spacing: 0) {
                SnippetsList(
                    results: rows, selectedID: selected?.id, scroll: scroll,
                    onSelect: { record in
                        vm.selection = rows.firstIndex(of: record) ?? 0
                    },
                    onActivate: { activate(at: vm.selection) },
                    onActions: { record in
                        if let index = rows.firstIndex(of: record) { vm.selection = index }
                        openActions()
                    }
                )
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                SnippetPreview(record: selected)
            }
        }
    }

    /// An empty library and an over-narrow filter are different problems with different answers.
    private var emptyMessage: String {
        if store.state == .loading { return "Loading snippets…" }
        if core.snippetCoordinator.showsOnlyAppSnippets, vm.query.isEmpty {
            return "No snippets for \(app?.name ?? "this app") yet"
        }
        return store.snippets.contains(where: { $0.snippet.isEnabled })
            ? "No matching snippets" : "No snippets yet"
    }
}

@MainActor
enum SnippetActionsMenu {
    static func content(record: StoredSnippet, core: AppCore) -> PopoverMenuContent {
        PopoverMenuContent(
            header: record.snippet.name,
            items: [
                PopoverMenuItem(title: "Paste Snippet", systemImage: "text.quote", shortcut: "↵") {
                    core.snippetCoordinator.expandSnippetFromPalette(id: record.id)
                }
            ] + extraItems(id: record.id, core: core) + [
                PopoverMenuItem(title: "Edit Snippet", systemImage: "pencil", startsSection: true) {
                    core.paletteCoordinator.hidePalette(restoreFocus: false)
                    core.snippetCoordinator.editSnippet(record)
                },
                PopoverMenuItem(title: "Create Snippet", systemImage: "plus") {
                    core.paletteCoordinator.hidePalette(restoreFocus: false)
                    core.snippetCoordinator.editSnippet(nil)
                },
                PopoverMenuItem(title: "Show in Finder", systemImage: "folder", startsSection: true) {
                    core.snippetCoordinator.showSnippetInFinder(record)
                }
            ])
    }

    /// Copy and Ask AI, shared with a snippet's launcher row so both menus offer the same things.
    static func extraItems(id: StoredSnippet.ID, core: AppCore) -> [PopoverMenuItem] {
        var items = [
            PopoverMenuItem(title: "Copy Snippet", systemImage: "doc.on.doc") {
                core.snippetCoordinator.copySnippet(id: id)
            }
        ]
        if core.settings.aiEnabled {
            items.append(
                PopoverMenuItem(title: "Ask AI", systemImage: "sparkles") {
                    core.snippetCoordinator.askAI(id: id)
                })
        }
        return items
    }
}
