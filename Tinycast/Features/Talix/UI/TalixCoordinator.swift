import AppKit

@MainActor
@Observable
final class TalixCoordinator {
    let store: TalixStore
    private let settings: AppSettings
    private unowned let core: AppCore
    var pickingProject = false
    var loggingTime = false
    var projectId = ""
    var duration = ""
    var description = ""
    private(set) var isBusy = false
    private(set) var hasKey = false
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var changingKey = false
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var pendingDraft: (input: String, entry: TalixTimeEntry)?

    init(store: TalixStore, settings: AppSettings, core: AppCore) {
        self.store = store
        self.settings = settings
        self.core = core
    }

    func start() { store.start() }

    func stop() {
        operation?.cancel()
        refreshTask?.cancel()
    }

    func show(pickingProject: Bool = false, loggingTime: Bool = false) {
        self.pickingProject = pickingProject
        self.loggingTime = loggingTime
        core.paletteCoordinator.showPalette(mode: .talix, seeding: "")
        refresh()
    }

    func refresh(force: Bool = false) {
        guard !changingKey else { refreshAgain = true; return }
        guard refreshTask == nil else { refreshAgain = true; return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                refreshTask = nil
                if refreshAgain { refreshAgain = false; refresh(force: true) }
            }
            hasKey = (try? await Task.detached {
                try TalixClient.secrets.hasSecret(for: TalixClient.account)
            }.value) == true
            if hasKey { await store.refresh(environment: settings.talixEnvironment, force: force) } else { await store.restore() }
            if loggingTime, core.palette.mode == .talix {
                core.palette.selection = store.entries.count + (store.running == nil ? 0 : 1)
            }
        }
    }

    func startTimer(project: TalixProject) {
        perform { [weak self] in
            guard let self else { return }
            await store.restore()
            guard store.running == nil else { throw ActionError.timerRunning }
            guard hasKey else { throw TalixClient.ClientError.missingKey }
            guard store.environment == settings.talixEnvironment, !store.isLoading else {
                throw ActionError.refreshing
            }
            let rate = try rate(for: project)
            let timer = TalixTimer(projectId: project.id, projectName: project.name,
                                   description: "", startedAt: Date())
            try await store.setRunning(.init(environment: settings.talixEnvironment, timer: timer,
                rate: rate, billable: billable(for: project.id)))
            pickingProject = false
            core.showMessage("Started timer for \(project.name)")
        }
    }

    func stopTimer() {
        perform { [weak self] in
            guard let self else { return }
            await store.restore()
            guard var running = store.running else { throw ActionError.noTimer }
            guard running.environment == settings.talixEnvironment else { throw ActionError.environment }
            core.paletteCoordinator.hidePalette(restoreFocus: false)
            if running.pendingEntry == nil {
                let endingAt = Date()
                let project = store.projects.first { $0.id == running.timer.projectId }
                    ?? TalixProject(id: running.timer.projectId, name: running.timer.projectName)
                let rate = try running.rate ?? rate(for: project)
                guard let values = await core.fillSnippetArguments(
                    snippetName: "Describe time for \(project.name)",
                    arguments: [.init(name: "Description", options: [])]) else { return }
                running.timer.description = values["Description"] ?? ""
                running.pendingEntry = try running.timer.entry(
                    endingAt: endingAt, rate: rate, calendar: .current, timeZone: .current,
                    rounding: settings.talixRounding, billable: running.billable ?? billable(for: project.id))
            }
            guard let entry = running.pendingEntry else { return }
            guard await confirm(entry: entry, project: running.timer.projectName) else { return }
            try await store.setRunning(running)
            try await store.create(projectId: running.timer.projectId, entry: entry, environment: running.environment)
            try await store.setRunning(nil)
            core.showMessage("Logged \(TalixTimeEntry.durationLabel(entry.duration)) to \(running.timer.projectName)")
            refresh(force: false)
        }
    }

    func discardTimer() {
        perform { [weak self] in
            guard let self, store.running != nil else { return }
            core.paletteCoordinator.hidePalette(restoreFocus: false)
            guard await core.confirm(title: "Discard the Talix timer?",
                message: "No time will be logged. A previously submitted request may already exist in Talix.",
                symbol: "timer", confirmTitle: "Discard") else { return }
            try await store.setRunning(nil)
            core.showMessage("Timer discarded")
        }
    }

    func logTime() {
        perform { [weak self] in
            guard let self else { return }
            guard store.environment == settings.talixEnvironment, !store.isLoading else {
                throw ActionError.refreshing
            }
            guard let project = store.projects.first(where: { $0.id == projectId }) else {
                throw ActionError.chooseProject
            }
            let rate = try rate(for: project)
            let input = [settings.talixEnvironment.rawValue, projectId, duration, description,
                         String(rate), String(billable(for: projectId)), String(settings.talixRounding.rawValue)]
                .joined(separator: "\u{0}")
            let entry: TalixTimeEntry
            if let pendingDraft, pendingDraft.input == input { entry = pendingDraft.entry } else {
                entry = try TalixEntryDraft.parse(duration, now: Date(), calendar: .current,
                    timeZone: .current, rounding: settings.talixRounding).entry(
                    description: description, rate: rate, billable: billable(for: projectId), timeZone: .current)
                pendingDraft = (input, entry)
            }
            core.paletteCoordinator.hidePalette(restoreFocus: false)
            guard await confirm(entry: entry, project: project.name) else { return }
            try await store.create(projectId: project.id, entry: entry, environment: settings.talixEnvironment)
            pendingDraft = nil
            duration = ""
            description = ""
            loggingTime = false
            core.showMessage("Logged \(TalixTimeEntry.durationLabel(entry.duration)) to \(project.name)")
            refresh()
        }
    }

    func rateKey(_ projectId: String) -> String { settings.talixEnvironment.rawValue + ":" + projectId }

    func rate(for project: TalixProject) throws -> Double {
        guard let rate = project.rate ?? settings.talixProjectRates[rateKey(project.id)], rate.isFinite, rate >= 0 else {
            throw TalixEntryDraft.DraftError.invalidRate
        }
        return rate
    }

    func billable(for projectId: String) -> Bool {
        settings.talixProjectBillable[rateKey(projectId)] ?? settings.talixDefaultBillable
    }

    func saveKey(_ value: String) {
        perform { [weak self] in
            guard let self else { return }
            await store.restore()
            guard store.running == nil else { throw ActionError.timerRunning }
            changingKey = true
            defer {
                changingKey = false
                refreshAgain = false
                refresh(force: true)
            }
            await refreshTask?.value
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.isEmpty || value.hasPrefix("tlx_") else { throw ActionError.invalidKey }
            try await store.invalidateProjects()
            try await Task.detached {
                if value.isEmpty {
                    try TalixClient.secrets.removeSecret(for: TalixClient.account)
                } else {
                    try TalixClient.secrets.setSecret(value, for: TalixClient.account)
                }
            }.value
            hasKey = !value.isEmpty
            projectId = ""
            pendingDraft = nil
            core.showMessage(value.isEmpty ? "Talix key removed" : "Talix key saved")
        }
    }

    private func confirm(entry: TalixTimeEntry, project: String) async -> Bool {
        await core.confirm(title: "Log \(TalixTimeEntry.durationLabel(entry.duration)) to \(project)?",
            message: "\(settings.talixEnvironment.title) · Rate \(entry.rate) · "
                + (entry.billable ? "Billable" : "Non-billable")
                + "\n\(entry.startTime ?? "") to \(entry.endTime ?? "")\n\(entry.description)",
            symbol: "clock", confirmTitle: "Log Time", tone: .neutral, confirmRole: .standard)
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true
        operation = Task { [weak self] in
            defer { self?.isBusy = false; self?.operation = nil }
            do { try await action() } catch {
                guard let self else { return }
                core.paletteCoordinator.hidePalette(restoreFocus: false)
                _ = await core.reportFailure(title: "Couldn't complete Talix action",
                    message: error.localizedDescription, symbol: "clock.badge.exclamationmark", recovery: nil)
            }
        }
    }

    private enum ActionError: String, LocalizedError {
        case timerRunning = "Stop or discard the current timer first."
        case noTimer = "No Talix timer is running."
        case environment = "Switch back to the timer's environment in Talix Settings before logging it."
        case chooseProject = "Choose a project before logging time."
        case refreshing = "Wait for Talix projects to finish loading in the selected environment."
        case invalidKey = "A Talix API key starts with tlx_."
        var errorDescription: String? { rawValue }
    }
}
