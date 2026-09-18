import Foundation

enum DictationHistoryParser {
    static func parse(_ text: String, sourceURL: URL, calendar: Calendar) -> [TranscriptEntry] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard let header = lines.first, header.hasPrefix("# Dictations "),
            let day = numbers(String(header.dropFirst(13)), separator: "-", widths: [4, 2, 2])
        else { return [] }
        var entries: [TranscriptEntry] = []
        var date: Date?
        var headingIndex = 0
        var body: [String] = []

        func appendEntry() {
            let content = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let date, !content.isEmpty else { return }
            entries.append(TranscriptEntry(
                id: "\(sourceURL.absoluteString)#\(headingIndex)",
                title: String(content.prefix(120)).components(separatedBy: "\n")[0],
                text: content, date: date, sourceURL: sourceURL, source: .dictation,
                duration: nil, segments: []))
        }

        for (index, line) in lines.dropFirst().enumerated() {
            if line.hasPrefix("## ") {
                appendEntry()
                body = []
                headingIndex = index + 1
                date = timestamp(String(line.dropFirst(3)), day: day, calendar: calendar)
            } else if date != nil {
                body.append(line)
            }
        }
        appendEntry()
        return entries
    }

    private static func timestamp(_ text: String, day: [Int], calendar: Calendar) -> Date? {
        guard let time = numbers(text, separator: ":", widths: [2, 2, 2]),
            day[0] > 0, (1...12).contains(day[1]), (1...31).contains(day[2]),
            (0...23).contains(time[0]), (0...59).contains(time[1]), (0...59).contains(time[2])
        else { return nil }
        let components = DateComponents(
            year: day[0], month: day[1], day: day[2], hour: time[0], minute: time[1], second: time[2])
        guard let date = calendar.date(from: components),
            calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date) == components
        else { return nil }
        return date
    }

    private static func numbers(_ text: String, separator: Character, widths: [Int]) -> [Int]? {
        let parts = text.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count == widths.count,
            zip(parts, widths).allSatisfy({ part, width in
                part.count == width && part.utf8.allSatisfy { (48...57).contains($0) }
            })
        else { return nil }
        let values = parts.compactMap { Int($0) }
        return values.count == widths.count ? values : nil
    }
}
