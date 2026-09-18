import AppKit

@MainActor
@Observable
final class ClipShareCoordinator {
    private(set) var videos: [ClipShareVideo] = []
    private(set) var isLoading = false
    private(set) var isUploading = false
    private(set) var failure: String?
    private(set) var baseURL: String
    private unowned let core: AppCore
    private let secrets = KeychainSecretStore(scope: "clipshare.token")
    private let account = UUID(uuidString: "10869F43-27C9-4986-BAC7-B2E09D7F960A")!
    private let defaults: UserDefaults
    @ObservationIgnored private var uploadTask: Task<Void, Never>?
    @ObservationIgnored private var recentTask: Task<Void, Never>?
    @ObservationIgnored private var actionTask: Task<Void, Never>?

    init(core: AppCore, defaults: UserDefaults = .standard) {
        self.core = core
        self.defaults = defaults
        baseURL = defaults.string(forKey: "clipshare.baseURL") ?? "https://clips.talix.app"
    }

    func stop() {
        uploadTask?.cancel()
        recentTask?.cancel()
        actionTask?.cancel()
    }

    func saveConnection(baseURL: String, token: String) -> Bool {
        guard !isUploading, actionTask == nil else {
            core.showMessage("Wait for the ClipShare request to finish", tone: .neutral)
            return false
        }
        do {
            let address = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: address) else { throw ConnectionError.invalidURL }
            let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try ClipShareClient(baseURL: url, token: token.isEmpty ? "validation" : token)
            if !token.isEmpty { try secrets.setSecret(token, for: account) }
            self.baseURL = address
            defaults.set(address, forKey: "clipshare.baseURL")
            resetRecent()
            core.showMessage("Saved ClipShare connection")
            return true
        } catch {
            core.showMessage(error.localizedDescription, tone: .danger)
            return false
        }
    }

    func removeToken() {
        guard !isUploading, actionTask == nil else {
            core.showMessage("Wait for the ClipShare request to finish", tone: .neutral)
            return
        }
        do {
            try secrets.removeSecret(for: account)
            resetRecent()
            core.showMessage("Removed ClipShare token")
        } catch {
            core.showMessage("Could not remove the ClipShare token", tone: .danger)
        }
    }

    private func client() throws -> ClipShareClient {
        guard let url = URL(string: baseURL) else { throw ConnectionError.invalidURL }
        guard let token = try secrets.secret(for: account), !token.isEmpty else {
            throw ConnectionError.missingToken
        }
        return try ClipShareClient(baseURL: url, token: token)
    }

    func shareLatest() {
        startUpload(source: nil)
    }

    func shareClipboard() {
        guard let urls = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
            let url = urls.first
        else {
            core.showMessage("Copy a video file in Finder first", tone: .danger)
            return
        }
        startUpload(source: url)
    }

    private func startUpload(source: URL?) {
        guard !isUploading else {
            core.showMessage("A ClipShare upload is already running", tone: .neutral)
            return
        }
        isUploading = true
        core.paletteCoordinator.hidePalette(restoreFocus: true)
        let home = FileManager.default.homeDirectoryForCurrentUser
        uploadTask = Task { [weak self] in
            guard let self else { return }
            defer { isUploading = false; uploadTask = nil }
            do {
                let client = try client()
                core.showProgress("Preparing video")
                let exportProgress: @Sendable (Double) async -> Void = { [weak self] progress in
                    await self?.progress("Preparing", fraction: progress)
                }
                let uploadProgress: @Sendable (Double) async -> Void = { [weak self] progress in
                    await self?.progress("Uploading", fraction: progress)
                }
                let worker = Task.detached(priority: .background) {
                    let url: URL
                    if let source {
                        url = source
                    } else {
                        url = try await ClipShareRecordingScanner.latestRecording(homeDirectory: home)
                    }
                    let prepared = try await ClipShareMediaExporter.prepare(url, progress: exportProgress)
                    defer { try? prepared.cleanup() }
                    let request = ClipShareCreateRequest(
                        idempotencyKey: UUID().uuidString.lowercased(), originalFilename: url.lastPathComponent,
                        sizeBytes: prepared.sizeBytes, durationSeconds: prepared.durationSeconds,
                        width: prepared.width, height: prepared.height)
                    return try await client.upload(
                        fileURL: prepared.fileURL, metadata: request, progress: uploadProgress)
                }
                let result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                copyURL(result.shareUrl)
            } catch is CancellationError {
                core.hideProgress()
            } catch {
                core.hideProgress()
                _ = await core.reportFailure(
                    title: "Could Not Share Video", message: error.localizedDescription,
                    symbol: "video", recovery: nil)
            }
        }
    }

    private func progress(_ stage: String, fraction: Double) {
        guard isUploading else { return }
        core.showProgress("\(stage) video · \(Int(fraction * 100))%")
    }

    func show() {
        core.paletteCoordinator.togglePalette(mode: .clipShareRecent)
        refresh()
    }

    private func resetRecent() {
        recentTask?.cancel()
        videos = []
        failure = nil
        isLoading = false
    }

    func refresh() {
        guard actionTask == nil else { return }
        recentTask?.cancel()
        isLoading = true
        failure = nil
        recentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await client().recent()
                try Task.checkCancellation()
                videos = result
                isLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                failure = error.localizedDescription
                videos = []
                isLoading = false
            }
        }
    }

    func copy(_ video: ClipShareVideo) {
        guard video.status == .ready, let url = video.shareUrl else { return }
        copyURL(url)
    }

    private func copyURL(_ url: URL) {
        Paster.copyPlainText(url.absoluteString)
        core.showMessage("Copied share URL")
    }

    func open(_ video: ClipShareVideo) {
        guard video.status == .ready, let url = video.shareUrl,
            ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        NSWorkspace.shared.open(url)
    }

    func revoke(_ video: ClipShareVideo) { change(video, deleting: false) }
    func delete(_ video: ClipShareVideo) { change(video, deleting: true) }

    private func change(_ video: ClipShareVideo, deleting: Bool) {
        guard actionTask == nil else { return }
        actionTask = Task { [weak self] in
            guard let self else { return }
            defer { actionTask = nil }
            let confirmed = await core.confirm(
                title: deleting ? "Delete Video?" : "Revoke Share Link?",
                message: deleting ? "\(video.title) and its share link will be deleted."
                    : "The old link will stop working. A new link will be copied.",
                symbol: deleting ? "trash" : "link", confirmTitle: deleting ? "Delete" : "Revoke")
            guard confirmed, !Task.isCancelled else { return }
            recentTask?.cancel()
            isLoading = false
            do {
                let client = try client()
                if deleting {
                    try await client.delete(id: video.id)
                    videos.removeAll { $0.id == video.id }
                    core.showMessage("Deleted video")
                } else {
                    let result = try await client.revoke(id: video.id)
                    if let index = videos.firstIndex(where: { $0.id == video.id }) {
                        videos[index] = result.video
                    }
                    copyURL(result.shareUrl)
                }
            } catch {
                _ = await core.reportFailure(
                    title: "ClipShare Request Failed", message: error.localizedDescription,
                    symbol: "video", recovery: nil)
            }
        }
    }

    private enum ConnectionError: LocalizedError {
        case invalidURL, missingToken
        var errorDescription: String? {
            switch self {
            case .invalidURL: "Enter a valid ClipShare base URL in Settings."
            case .missingToken: "Paste your ClipShare token in Settings > ClipShare first."
            }
        }
    }
}
