import Foundation

enum ClipShareRecordingScanner {
    nonisolated static func latestRecording(homeDirectory: URL) async throws -> URL {
        let result = try await ToolRunner.run(
            URL(filePath: "/usr/bin/defaults"), ["read", "com.apple.screencapture", "location"], timeout: 5)
        let location = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let directory: URL
        if result.succeeded && !location.isEmpty {
            let path = location.hasPrefix("~/")
                ? homeDirectory.appending(path: String(location.dropFirst(2))).path : location
            directory = URL(filePath: path, directoryHint: .isDirectory)
        } else if result.status == 1 && result.output.contains("does not exist") {
            directory = homeDirectory.appending(path: "Desktop", directoryHint: .isDirectory)
        } else {
            throw CocoaError(.fileReadUnknown, userInfo: [
                NSLocalizedDescriptionKey: "Could not read the screenshot directory: \(result.tail)"
            ])
        }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        let listing = try files.map { url in
            let values = try url.resourceValues(forKeys: keys)
            return ClipShareUploadPlan.Recording(
                url: url, modifiedAt: values.contentModificationDate ?? .distantPast,
                isRegularFile: values.isRegularFile == true)
        }
        guard let latest = ClipShareUploadPlan.newestRecording(in: listing) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "No MOV or MP4 recordings were found in \(directory.path)."
            ])
        }
        return latest
    }
}
