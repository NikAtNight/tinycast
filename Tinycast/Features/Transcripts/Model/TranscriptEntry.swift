import Foundation

struct TranscriptEntry: Identifiable, Sendable {
    enum Source: Sendable {
        case dictation
        case scribe
    }

    let id: String
    let title: String
    let text: String
    let date: Date
    let sourceURL: URL
    let source: Source
    let duration: Double?
    let segments: [ScribeDocumentDecoder.Segment]

    func text(in range: ClosedRange<Int>) -> String? {
        guard range.lowerBound >= 0, range.upperBound < segments.count else { return nil }
        let text = segments[range].map(\.text).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
