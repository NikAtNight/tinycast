import Foundation

@MainActor
@Observable
final class PortsSession {
    private(set) var ports: [ListeningPort] = []
    private(set) var isScanning = false
    private(set) var failure: String?
    @ObservationIgnored private var refreshPending = false
    @ObservationIgnored private var executable: URL?
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    func refresh() {
        guard !isScanning else {
            refreshPending = true
            return
        }
        isScanning = true
        failure = nil
        let executable = executable
        scanTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                let located = executable != nil ? executable : await ExecutableLocator.locate("lsof")
                guard let url = located else {
                    throw PortScanner.Failure.unavailable
                }
                return (url, try await PortScanner.scan(executable: url))
            }
            do {
                let (url, ports) = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard let self, !Task.isCancelled else { return }
                self.executable = url
                self.ports = ports
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.failure = error.localizedDescription
            }
            self?.isScanning = false
            self?.scanTask = nil
            if let self, refreshPending {
                refreshPending = false
                refresh()
            }
        }
    }

    isolated deinit { scanTask?.cancel() }
}
