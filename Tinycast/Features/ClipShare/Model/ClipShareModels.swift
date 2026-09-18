import Foundation

enum ClipShareVideoStatus: String, Codable, Sendable {
    case uploading, ready, failed
}

struct ClipShareVideo: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let originalFilename: String
    let sizeBytes: Int64
    let durationSeconds: Double?
    let width: Int?
    let height: Int?
    let status: ClipShareVideoStatus
    let shareEnabled: Bool
    let shareUrl: URL?
    let createdAt: Date
    let readyAt: Date?
}

struct ClipShareCreateRequest: Codable, Sendable {
    let idempotencyKey: String
    let originalFilename: String
    let sizeBytes: Int64
    let durationSeconds: Double?
    let width: Int?
    let height: Int?
}

struct ClipShareCreateResponse: Codable, Sendable {
    let video: ClipShareVideo
    let partSizeBytes: Int64
    let partCount: Int
}

struct ClipShareStatusResponse: Codable, Sendable {
    let video: ClipShareVideo
    let partSizeBytes: Int64
    let partCount: Int
    let uploadedParts: [Int]
}

struct ClipShareCompleteResponse: Codable, Sendable {
    let video: ClipShareVideo
    let shareUrl: URL
}

struct ClipShareListResponse: Codable, Sendable {
    let videos: [ClipShareVideo]
    let nextCursor: String?
}

enum ClipShareError: Error, LocalizedError, Sendable {
    case invalidConfiguration
    case invalidUpload
    case fileChanged
    case unsupportedVideo
    case invalidResponse
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Enter a valid ClipShare server URL and token in Settings."
        case .invalidUpload: "The upload size or part information is invalid."
        case .fileChanged: "The video changed while it was being uploaded."
        case .unsupportedVideo: "macOS could not prepare this video as a browser-compatible MP4."
        case .invalidResponse: "ClipShare returned an unexpected response."
        case .server(401): "ClipShare rejected the token. Update it in Settings."
        case .server(404): "The video no longer exists."
        case .server(let status): "ClipShare could not complete the request (HTTP \(status))."
        }
    }
}
