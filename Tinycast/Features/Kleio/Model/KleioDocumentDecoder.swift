import Foundation

enum KleioDocumentDecoder {
    struct Segment: Decodable, Sendable {
        let text: String
        let start: Double
        let end: Double
        let speaker: String?
    }

    private struct Document: Decodable {
        let id: String
        let title: String
        let createdAt: Date
        let duration: Double
        let segments: [Segment]
    }

    enum InvalidDocument: Error {
        case invalidValues
    }

    static func decode(_ data: Data, documentURL: URL) throws -> KleioRecording {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(Document.self, from: data)
        guard !document.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            document.duration.isFinite, document.duration >= 0, document.duration < Double(Int64.max),
            document.segments.allSatisfy({ segment in
                segment.start.isFinite && segment.end.isFinite
                    && segment.start >= 0 && segment.end >= segment.start
            })
        else { throw InvalidDocument.invalidValues }
        return KleioRecording(
            id: documentURL.absoluteString, title: document.title,
            text: document.segments.map(\.text).joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            date: document.createdAt, documentURL: documentURL,
            duration: document.duration, segments: document.segments)
    }
}
