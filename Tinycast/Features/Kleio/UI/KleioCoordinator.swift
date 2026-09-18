import AppKit

@MainActor @Observable
final class KleioCoordinator {
    private unowned let core: AppCore
    private let launcher = KleioLauncher()
    var segmentRecordingID: String?
    @ObservationIgnored private var actionTask: Task<Void, Never>?

    init(core: AppCore) {
        self.core = core
    }

    isolated deinit { actionTask?.cancel() }

    func show() {
        core.paletteCoordinator.togglePalette(mode: .kleioRecordings)
    }

    func trigger(_ command: KleioCommandURL) {
        if core.paletteCoordinator.isVisible { core.paletteCoordinator.hidePalette(restoreFocus: false) }
        actionTask?.cancel()
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await launcher.open(command)
                guard !Task.isCancelled else { return }
                core.showMessage(command.successMessage, tone: .success)
            } catch KleioLauncher.Failure.notInstalled {
                guard !Task.isCancelled else { return }
                _ = await core.reportFailure(
                    title: "Kleio is not available",
                    message: "Kleio is not installed or does not register the kleio scheme yet.",
                    symbol: "waveform", recovery: nil)
            } catch {
                guard !Task.isCancelled else { return }
                core.showMessage("Kleio did not accept the command", tone: .danger)
            }
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

    func reveal(_ recording: KleioRecording) {
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        NSWorkspace.shared.activateFileViewerSelecting([recording.folderURL])
    }
}
