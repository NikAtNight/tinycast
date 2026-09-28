import AppKit

/// Owns the snippet flow: listener, browser, editor handoff, delivery, presence.
@MainActor
final class SnippetCoordinator {
    private let store: SnippetsStore
    private let listener: SnippetKeywordListener
    private let injector: TextInjector
    private let clipboardStore: ClipboardStore
    private let appIndex: AppIndex
    private let settings: AppSettings
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    /// Routed out so `MessageHUDController` stays owned by `AppCore`.
    private let showMessage: @MainActor (String) -> Void
    /// The consent dialog and the `pendingSnippetEdit` handoff to the Settings pane.
    private unowned let core: AppCore
    /// Set by whichever command opened the browser, so Search Snippets always starts unfiltered.
    private(set) var showsOnlyAppSnippets = false

    init(
        store: SnippetsStore,
        listener: SnippetKeywordListener,
        injector: TextInjector,
        clipboardStore: ClipboardStore,
        appIndex: AppIndex,
        settings: AppSettings,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator,
        showMessage: @escaping @MainActor (String) -> Void,
        core: AppCore
    ) {
        self.store = store
        self.listener = listener
        self.injector = injector
        self.clipboardStore = clipboardStore
        self.appIndex = appIndex
        self.settings = settings
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.showMessage = showMessage
        self.core = core
    }

    // MARK: - Feature switch

    func revealSnippetsInFinder() {
        NSWorkspace.shared.open(store.snippetsDirectory)
    }

    /// The switch funnels here so enabling, which is also consent, confirms first.
    func setSnippetsEnabled(_ enabled: Bool) {
        guard enabled != settings.snippetsEnabled else { return }
        if !enabled {
            settings.snippetsEnabled = false
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.confirm(
                    title: "Enable snippets?",
                    message:
                        "Keyword expansion requires the Accessibility permission. Keystrokes stay on this Mac.",
                    symbol: "curlybraces", confirmTitle: "Continue", tone: .neutral,
                    confirmRole: .standard)
            else { return }

            settings.snippetsEnabled = true
            // The one prompt for this feature, raised from the gesture that asked for it.
            Permissions.ensureAccessibility()
        }
    }

    // MARK: - Feature presence

    /// Either switch off means the feature reaches the launcher not at all — rows and commands.
    func applySnippetsLauncherPresence() {
        let visible = settings.snippetsEnabled && settings.snippetsShowInLauncher
        let commands: Set<CommandID> = [.searchSnippets, .snippetsForThisApp, .createSnippet]
        appIndex.setCommandsVisible(commands, settings.snippetsEnabled)
        appIndex.setCommandsListed(commands, settings.snippetsShowInLauncher)
        appIndex.updateSnippets(visible ? store.snippets : [])
    }

    /// Reconciles everything the switch owns; off tears down in dependency order.
    func applySnippetsEnabled() {
        if settings.snippetsEnabled {
            Task { await store.start() }
            // An unchanged library publishes no snapshot, so re-project what the store holds.
            applySnippetsLauncherPresence()
            startSnippetKeywordListener()
            return
        }
        listener.stop()
        injector.cancelAutomaticExpansion()
        store.stop()
        applySnippetsLauncherPresence()
    }

    // MARK: - Browsing and editing

    /// The switch gates the browser, the way Search Files re-checks its own before opening.
    func showSnippets() {
        guard settings.snippetsEnabled else { return }
        showsOnlyAppSnippets = false
        paletteCoordinator.togglePalette(mode: .snippets)
    }

    /// The same browser, narrowed to the snippets written for the app the palette opens over.
    func showSnippetsForApp() {
        guard settings.snippetsEnabled else { return }
        showsOnlyAppSnippets = true
        paletteCoordinator.togglePalette(mode: .snippets)
    }

    /// Opens the Snippets pane with the editor showing `record`; nil is a new snippet.
    func editSnippet(_ record: StoredSnippet?) {
        core.pendingSnippetEdit = SnippetEditRequest(record: record)
        settingsCoordinator.showSettings(tab: .snippets)
    }

    func showSnippetInFinder(_ record: StoredSnippet) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(record.fileURL)
    }

    // MARK: - Expansion

    /// How far back `{clipboard offset=N}` reaches; deeper isn't a snippet idiom.
    private static let clipboardHistoryDepth = 20

    func startSnippetKeywordListener() {
        // `beginAutomaticExpansion` is the gate, so this callback doesn't re-check anything.
        listener.start(
            onUserActivity: { [weak self] in self?.injector.cancelAutomaticExpansion() },
            onMatch: { [weak self] id, keyword, keywordLength, target in
                guard let self,
                    let generation = self.injector.beginAutomaticExpansion(target: target)
                else { return }
                self.expandSnippet(
                    id: id,
                    target: target,
                    expectedKeyword: keyword,
                    keywordLength: keywordLength,
                    automaticGeneration: generation)
            })
    }

    /// Recent copies, newest first; the live pasteboard leads, the poller may lag behind.
    func clipboardHistoryForExpansion() -> [String] {
        var history = clipboardStore.items
            .filter { $0.kind == .text }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(Self.clipboardHistoryDepth)
            .compactMap(\.text)
        if let current = NSPasteboard.general.string(forType: .string), current != history.first {
            history.insert(current, at: 0)
        }
        return history
    }

    /// The browser's ↵. The target has to be read before the panel hides, as the launcher's does.
    func expandSnippetFromPalette(id: StoredSnippet.ID) {
        let target = windowController.previousTarget
        // One of our own editors is only reachable again once the palette hands key back to it.
        paletteCoordinator.hidePalette(restoreFocus: target?.ownEditor != nil)
        expandSnippet(id: id, target: target)
    }

    /// Expands onto the clipboard instead of into an app, so it enters history like any copy.
    func copySnippet(id: StoredSnippet.ID) {
        expandedText(of: id, hidesPalette: true) { [weak self] text, name in
            Paster.copyPlainText(text)
            self?.showMessage("Copied \(name)")
        }
    }

    /// Hands the expanded text to Quick AI as a question already asked; ⌘J moves it to a window.
    func askAI(id: StoredSnippet.ID) {
        guard settings.aiEnabled else { return }
        expandedText(of: id, hidesPalette: false) { [weak self] text, _ in
            self?.core.quickAICoordinator.ask(text)
        }
    }

    /// The paste funnel's expansion and argument prompt, with the result handed back as text.
    private func expandedText(
        of id: StoredSnippet.ID, hidesPalette: Bool,
        then use: @escaping @MainActor (String, String) -> Void
    ) {
        let records = store.snippets
        guard let record = records.first(where: { $0.id == id }) else { return }
        // Read before the panel hides: `{selection}` comes from the app behind it.
        let target = windowController.previousTarget
        let context = injector.captureExpansionContext(
            target: target, clipboardHistory: clipboardHistoryForExpansion())
        let result = SnippetTemplateEngine.expand(record, snippets: records, context: context)
        if hidesPalette { paletteCoordinator.hidePalette() }
        guard !result.missingArguments.isEmpty else {
            use(result.text, record.snippet.name)
            return
        }
        guard !core.isShowingDialog else { return }
        if !hidesPalette { paletteCoordinator.hidePalette(restoreFocus: false) }
        listener.isPromptingForArguments = true
        Task {
            let arguments = await core.fillSnippetArguments(
                snippetName: record.snippet.name, arguments: result.missingArguments)
            listener.isPromptingForArguments = false
            guard let arguments else { return }
            let filled = SnippetTemplateEngine.expand(
                record, snippets: records, context: context, userArguments: arguments)
            use(filled.text, record.snippet.name)
        }
    }

    func expandSnippet(
        id: StoredSnippet.ID,
        target: InjectionTarget?,
        expectedKeyword: String? = nil,
        keywordLength: Int = 0,
        automaticGeneration: UInt? = nil
    ) {
        let records = store.snippets
        guard let record = records.first(where: { $0.id == id }) else {
            injector.cancelArgumentPrompt(
                automaticGeneration: automaticGeneration,
                target: target)
            return
        }
        // Only the interactive path needs this: it must fail before the prompt, not after.
        if automaticGeneration == nil {
            guard injector.prepareInteractiveExpansion(target: target) else { return }
        }
        let confirmation = record.snippet.showsConfirmation ? "Inserted \(record.snippet.name)" : nil
        let context = injector.captureExpansionContext(
            target: target,
            clipboardHistory: clipboardHistoryForExpansion())
        let result = SnippetTemplateEngine.expand(
            record,
            snippets: records,
            context: context)
        if !result.missingArguments.isEmpty {
            promptSnippetArguments(
                record: record,
                records: records,
                context: context,
                missingArgs: result.missingArguments,
                target: target,
                expectedKeyword: expectedKeyword,
                keywordLength: keywordLength,
                automaticGeneration: automaticGeneration,
                confirmation: confirmation)
            return
        }
        completeSnippetExpansion(
            result,
            target: target,
            expectedKeyword: expectedKeyword,
            keywordLength: keywordLength,
            automaticGeneration: automaticGeneration,
            confirmation: confirmation)
    }

    private func promptSnippetArguments(
        record: StoredSnippet,
        records: [StoredSnippet],
        context: SnippetTemplateEngine.ExpansionContext,
        missingArgs: [SnippetTemplateEngine.MissingArgument],
        target: InjectionTarget?,
        expectedKeyword: String?,
        keywordLength: Int,
        automaticGeneration: UInt?,
        confirmation: String?
    ) {
        // The open dialog would refuse this prompt, and its end must not clear the flag under it.
        guard !core.isShowingDialog else {
            injector.cancelArgumentPrompt(
                automaticGeneration: automaticGeneration,
                target: target)
            return
        }
        listener.isPromptingForArguments = true
        Task {
            let arguments = await core.fillSnippetArguments(
                snippetName: record.snippet.name,
                arguments: missingArgs)
            listener.isPromptingForArguments = false
            guard let arguments else {
                injector.cancelArgumentPrompt(
                    automaticGeneration: automaticGeneration,
                    target: target)
                return
            }

            let result = SnippetTemplateEngine.expand(
                record,
                snippets: records,
                context: context,
                userArguments: arguments)
            completeSnippetExpansion(
                result,
                target: target,
                expectedKeyword: expectedKeyword,
                keywordLength: keywordLength,
                automaticGeneration: automaticGeneration,
                confirmation: confirmation)
        }
    }

    private func completeSnippetExpansion(
        _ result: SnippetTemplateEngine.ExpansionResult,
        target: InjectionTarget?,
        expectedKeyword: String?,
        keywordLength: Int,
        automaticGeneration: UInt?,
        confirmation: String?
    ) {
        injector.deliver(
            InjectedText(result.text, cursorOffsetFromEnd: result.cursorOffsetFromEnd),
            target: target,
            expectedKeyword: expectedKeyword,
            keywordLength: keywordLength,
            automaticGeneration: automaticGeneration,
            onDelivered: { [weak self] in
                guard let self, let confirmation else { return }
                self.showMessage(confirmation)
            })
    }
}
