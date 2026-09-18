import AppKit

@MainActor @Observable
final class TranscriptsCoordinator {
    private unowned let core: AppCore
    private let store: TranscriptStore
    private let windowController: PaletteWindowController
    var segmentEntryID: String?
    @ObservationIgnored private var actionTask: Task<Void, Never>?

    init(core: AppCore, store: TranscriptStore, windowController: PaletteWindowController) {
        self.core = core
        self.store = store
        self.windowController = windowController
    }

    isolated deinit { actionTask?.cancel() }

    func show(_ mode: PaletteMode) {
        core.paletteCoordinator.togglePalette(mode: mode)
    }

    func openToday() {
        let url = TranscriptStore.todayURL(directory: store.historyDirectory, now: Date(), calendar: .current)
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        actionTask?.cancel()
        actionTask = Task { [weak self] in
            do {
                _ = try await NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                self?.core.showMessage("Today's dictation file could not be opened", tone: .danger)
            }
        }
    }

    func pasteLast() {
        let url = TranscriptStore.todayURL(directory: store.historyDirectory, now: Date(), calendar: .current)
        let calendar = Calendar.current
        let target = core.paletteCoordinator.isVisible
            ? windowController.previousApp : NSWorkspace.shared.frontmostApplication
        actionTask?.cancel()
        actionTask = Task { [weak self] in
            let reader = Task.detached(priority: .userInitiated) {
                let text = try String(contentsOf: url, encoding: .utf8)
                return DictationHistoryParser.parse(text, sourceURL: url, calendar: calendar).last
            }
            do {
                let entry = try await reader.value
                guard !Task.isCancelled, let self else { return }
                guard let entry else {
                    core.showMessage("No dictations today", tone: .neutral)
                    return
                }
                core.paletteCoordinator.hidePalette(restoreFocus: false)
                Paster.pasteString(entry.text, previousApp: target)
            } catch {
                guard !Task.isCancelled else { return }
                self?.core.showMessage("Today's dictations could not be read", tone: .danger)
            }
        }
    }

    func activate(_ entry: TranscriptEntry) {
        if entry.source == .dictation {
            let target = windowController.previousApp
            core.paletteCoordinator.hidePalette(restoreFocus: false)
            Paster.pasteString(entry.text, previousApp: target)
        } else {
            copy(entry.text)
        }
    }

    func copy(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            core.showMessage("This recording has no transcript", tone: .neutral)
            return
        }
        Paster.copyString(text)
        core.showMessage("Copied transcript")
    }

    func reveal(_ entry: TranscriptEntry) {
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        NSWorkspace.shared.activateFileViewerSelecting([
            entry.source == .dictation ? entry.sourceURL : entry.sourceURL.deletingLastPathComponent()
        ])
    }
}
