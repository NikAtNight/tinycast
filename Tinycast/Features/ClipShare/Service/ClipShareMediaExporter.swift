import AVFoundation
import Foundation

struct ClipSharePreparedVideo: Sendable {
    let fileURL: URL
    let sizeBytes: Int64
    let durationSeconds: Double?
    let width: Int?
    let height: Int?

    func cleanup() throws { try FileManager.default.removeItem(at: fileURL) }
}

enum ClipShareMediaExporter {
    nonisolated static func prepare(
        _ source: URL, temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> ClipSharePreparedVideo {
        try Task.checkCancellation()
        let output = temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        do {
            let asset = AVURLAsset(url: source)
            guard try await asset.load(.isReadable),
                  let video = try await asset.loadTracks(withMediaType: .video).first
            else { throw ClipShareError.unsupportedVideo }
            let descriptions = try await video.load(.formatDescriptions)
            let videoCodec = descriptions.first.map(CMFormatDescriptionGetMediaSubType)
            let audio = try await asset.loadTracks(withMediaType: .audio).first
            let audioDescriptions = try await audio?.load(.formatDescriptions)
            let audioCodec = audioDescriptions?.first.map(CMFormatDescriptionGetMediaSubType)
            let compatible = videoCodec == kCMVideoCodecType_H264
                && (audioCodec == nil || audioCodec == kAudioFormatMPEG4AAC)
            let preset = compatible ? AVAssetExportPresetPassthrough : AVAssetExportPreset1920x1080
            guard let exporter = AVAssetExportSession(asset: asset, presetName: preset),
                  exporter.supportedFileTypes.contains(.mp4)
            else { throw ClipShareError.unsupportedVideo }
            exporter.shouldOptimizeForNetworkUse = true
            let states = exporter.states(updateInterval: 0.25)
            async let operation: Void = exporter.export(to: output, as: .mp4)
            for await state in states {
                try Task.checkCancellation()
                if case let .exporting(value) = state { await progress(value.fractionCompleted) }
            }
            try await operation
            try Task.checkCancellation()
            let prepared = AVURLAsset(url: output)
            guard let outputVideo = try await prepared.loadTracks(withMediaType: .video).first else {
                throw ClipShareError.unsupportedVideo
            }
            let outputFormats = try await outputVideo.load(.formatDescriptions)
            guard outputFormats.first.map(CMFormatDescriptionGetMediaSubType) == kCMVideoCodecType_H264 else {
                throw ClipShareError.unsupportedVideo
            }
            let size = try await outputVideo.load(.naturalSize)
            let transform = try await outputVideo.load(.preferredTransform)
            let displaySize = size.applying(transform)
            let duration = try await prepared.load(.duration).seconds
            let fileSize = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard fileSize > 0 else { throw ClipShareError.unsupportedVideo }
            await progress(1)
            return ClipSharePreparedVideo(
                fileURL: output, sizeBytes: Int64(fileSize),
                durationSeconds: duration.isFinite && duration >= 0 ? duration : nil,
                width: Int(abs(displaySize.width).rounded()), height: Int(abs(displaySize.height).rounded()))
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}
