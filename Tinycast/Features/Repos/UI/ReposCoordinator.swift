import AppKit

@MainActor
@Observable
final class ReposCoordinator {
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var actionTask: Task<Void, Never>?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var liveRun: (id: UUID, stop: @Sendable () -> Void)?
    @ObservationIgnored private var lastDevRepo: Repository?
    @ObservationIgnored private lazy var output = CommandOutputPresenter(
        activation: core.activationPolicy,
        rerun: { [weak self] _ in
            guard let self, let repo = self.lastDevRepo else { return }
            self.startDevServer(repo)
        },
        stop: { [weak self] id in
            guard let self, self.liveRun?.id == id else { return }
            self.liveRun?.stop()
        },
        openSettings: { [weak self] in self?.core.settingsCoordinator.showSettings(tab: .repos) })

    init(core: AppCore) { self.core = core }

    func show() { core.paletteCoordinator.togglePalette(mode: .repos) }

    func applyPolicy() {
        core.repos.configure(roots: core.settings.reposRoots, ignores: core.settings.reposIgnorePatterns)
        if core.palette.mode == .repos, core.palette.isVisible { refresh() }
    }

    func prepare() async {
        await core.repos.beginShow()
        reportScanFailure()
    }

    private func reportScanFailure() {
        if let error = core.repos.error { core.showMessage(error, tone: .danger) }
    }
    func endShow() { core.repos.endShow() }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            self.core.repos.endShow()
            await self.core.repos.refresh(force: true)
            self.reportScanFailure()
        }
    }

    func open(_ repo: Repository) {
        if core.settings.reposDefaultAction == "ghostty" { openGhostty(repo) } else { openSupacode(repo) }
    }

    func openSupacode(_ repo: Repository) {
        perform { try await RepoOpener.supacode(repo) }
    }

    func openGhostty(_ repo: Repository) {
        perform { try await RepoOpener.ghostty(repo) }
    }

    func openRemote(_ repo: Repository) {
        perform { try await RepoOpener.remote(repo) }
    }

    func reveal(_ repo: Repository) {
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: repo.path)])
    }

    func copyPath(_ repo: Repository) {
        Paster.copyPlainText(repo.path)
        core.showMessage("Copied path")
    }

    func startDevServer(_ repo: Repository) {
        guard let command = repo.devScript else { return }
        if RepoOpener.ghosttyInstalled {
            perform { try await RepoOpener.ghostty(repo, command: command) }
            return
        }
        guard streamTask == nil else {
            core.showMessage("Stop the current dev server in Command Output first", tone: .neutral)
            _ = output.focusExisting()
            return
        }
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        lastDevRepo = repo
        let id = output.begin(commandID: UUID(), name: "Dev server: \(repo.name)", commandText: command, symbol: "terminal")
        let presenter = output
        streamTask = Task { [weak self] in
            let session = await Task.detached(priority: .userInitiated) {
                ShellCommandRunner.stream(command, loadingShellEnvironment: true, workingDirectory: repo.path)
            }.value
            guard self != nil, !Task.isCancelled else { session.stop(); return }
            self?.liveRun = (id, session.stop)
            defer { self?.liveRun = nil; self?.streamTask = nil }
            for await event in session.events {
                switch event {
                case .output(let text): presenter.append(text, to: id)
                case .finished(let result):
                    presenter.finish(CommandOutcome(
                        summary: result.succeeded ? "Dev server finished" : "Dev server stopped or failed",
                        hint: result.standardError, succeeded: result.succeeded, finishedAt: Date()), for: id)
                }
            }
        }
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard actionTask == nil else { return }
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        actionTask = Task { [weak self] in
            defer { self?.actionTask = nil }
            do { try await action() } catch {
                guard let self else { return }
                _ = await self.core.reportFailure(
                    title: "Could not open repository", message: error.localizedDescription,
                    symbol: "folder", recovery: nil)
            }
        }
    }

    func setRoots(_ roots: [String]) {
        let normalized = roots.map { ($0 as NSString).standardizingPath }
        core.settings.reposRoots = Array(Set(normalized)).sorted()
        applyPolicy()
    }

    func setIgnorePatterns(_ patterns: [String]) {
        core.settings.reposIgnorePatterns = Array(Set(patterns.filter { !$0.isEmpty })).sorted()
        applyPolicy()
    }

    func setDefaultAction(_ action: String) {
        guard ["supacode", "ghostty"].contains(action) else { return }
        core.settings.reposDefaultAction = action
    }

    func setShowWorktrees(_ show: Bool) {
        core.settings.reposShowWorktrees = show
        core.palette.selection = 0
    }

    func addRoots() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        setRoots(core.settings.reposRoots + panel.urls.map { ($0.path as NSString).abbreviatingWithTildeInPath })
    }

    isolated deinit {
        refreshTask?.cancel()
        actionTask?.cancel()
        liveRun?.stop()
        streamTask?.cancel()
    }
}
