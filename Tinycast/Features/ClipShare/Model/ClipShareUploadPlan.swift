import Foundation

struct ClipShareUploadPlan: Sendable {
    struct Part: Sendable, Equatable {
        let number: Int
        let offset: Int64
        let length: Int64
    }

    struct Recording: Sendable {
        let url: URL
        let modifiedAt: Date
        let isRegularFile: Bool
    }

    let parts: [Part]

    init(sizeBytes: Int64, partSizeBytes: Int64) throws {
        guard sizeBytes > 0, sizeBytes <= 5_368_709_120, partSizeBytes > 0 else {
            throw ClipShareError.invalidUpload
        }
        let count = (sizeBytes - 1) / partSizeBytes + 1
        guard count <= 10_000 else { throw ClipShareError.invalidUpload }
        parts = (0..<Int(count)).map { index in
            let offset = Int64(index) * partSizeBytes
            return Part(number: index + 1, offset: offset, length: min(partSizeBytes, sizeBytes - offset))
        }
    }

    static func newestRecording(in listing: [Recording]) -> URL? {
        listing.filter {
            $0.isRegularFile && ["mov", "mp4"].contains($0.url.pathExtension.lowercased())
        }.max {
            if $0.modifiedAt == $1.modifiedAt { return $0.url.path < $1.url.path }
            return $0.modifiedAt < $1.modifiedAt
        }?.url
    }
}
