import Foundation

struct KleioRecording: Identifiable, Sendable {
    let id: String
    let title: String
    let text: String
    let date: Date
    let documentURL: URL
    let duration: Double
    let segments: [KleioDocumentDecoder.Segment]

    var folderURL: URL { documentURL.deletingLastPathComponent() }

    func text(in range: ClosedRange<Int>) -> String? {
        guard range.lowerBound >= 0, range.upperBound < segments.count else { return nil }
        let text = segments[range].map(\.text).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
