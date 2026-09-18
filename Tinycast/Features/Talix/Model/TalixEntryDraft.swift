import Foundation

struct TalixEntryDraft: Sendable, Equatable {
    enum DraftError: String, LocalizedError {
        case invalidDuration = "Use hours like 1.5, 1h30, 90m, or a clock range like 9-11."
        case invalidDay = "Use today, yesterday, or an English weekday name."
        case invalidInterval = "End time must follow start time by at least one second."
        case invalidDescription = "Enter a description between 1 and 2000 characters."
        case invalidRate = "Set a valid hourly rate for this project in Talix Settings."
        case invalidClock = "That clock time does not exist on the selected day."

        var errorDescription: String? { rawValue }
    }

    let start: Date
    let end: Date

    static func parse(
        _ input: String, now: Date, calendar: Calendar, timeZone: TimeZone,
        rounding: TalixTimer.Rounding = .none
    ) throws -> Self {
        var calendar = calendar
        calendar.timeZone = timeZone
        var words = input.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty, words.count <= 2 else { throw DraftError.invalidDuration }
        var day = calendar.startOfDay(for: now)
        if words.count == 2 {
            let dateWord = words.removeLast()
            let weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
            let fullNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            var daysBack = 0
            if dateWord == "yesterday" { daysBack = 1 } else if dateWord != "today" {
                guard let weekday = weekdays.firstIndex(of: dateWord) ?? fullNames.firstIndex(of: dateWord)
                else { throw DraftError.invalidDay }
                daysBack = (calendar.component(.weekday, from: now) - 1 - weekday + 7) % 7
            }
            guard let resolved = calendar.date(byAdding: .day, value: -daysBack, to: day) else {
                throw DraftError.invalidDay
            }
            day = resolved
        }
        let text = words[0]
        if text.contains("-") {
            let parts = text.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw DraftError.invalidDuration }
            let start = try clock(String(parts[0]), on: day, calendar: calendar)
            let end = try clock(String(parts[1]), on: day, calendar: calendar)
            guard end > start else { throw DraftError.invalidInterval }
            return Self(start: start, end: start.addingTimeInterval(rounding.duration(end.timeIntervalSince(start))))
        }
        let seconds = try duration(text)
        let components = calendar.dateComponents([.hour, .minute, .second], from: now)
        guard let end = calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0,
                                      second: components.second ?? 0, of: day) else {
            throw DraftError.invalidClock
        }
        return Self(start: end.addingTimeInterval(-rounding.duration(seconds)), end: end)
    }

    private static func duration(_ text: String) throws -> TimeInterval {
        let pattern = #"^(?:([0-9]+(?:\.[0-9]+)?)|([0-9]+)h(?:([0-9]{1,2})m?)?|([0-9]+)m)$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { throw DraftError.invalidDuration }
        func number(_ index: Int) -> Double? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return Double(text[range])
        }
        let minutes = number(3) ?? 0
        guard minutes < 60 else { throw DraftError.invalidDuration }
        let seconds = (number(1) ?? number(2) ?? 0) * 3600 + (number(4) ?? minutes) * 60
        guard seconds.isFinite, seconds >= 1, seconds <= 86400 else { throw DraftError.invalidDuration }
        return seconds
    }

    private static func clock(_ text: String, on day: Date, calendar: Calendar) throws -> Date {
        guard text.range(of: #"^[0-9]{1,2}(:[0-9]{2})?$"#, options: .regularExpression) != nil else {
            throw DraftError.invalidDuration
        }
        let parts = text.split(separator: ":")
        guard let hour = Int(parts[0]), hour < 24 else { throw DraftError.invalidClock }
        let minute = parts.count == 2 ? Int(parts[1])! : 0
        guard minute < 60,
            let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
            calendar.isDate(date, inSameDayAs: day),
            calendar.component(.hour, from: date) == hour,
            calendar.component(.minute, from: date) == minute
        else { throw DraftError.invalidClock }
        return date
    }

    func entry(description: String, rate: Double, billable: Bool, timeZone: TimeZone) throws -> TalixTimeEntry {
        try TalixTimeEntry(description: description, start: start, end: end, rate: rate,
                           billable: billable, timeZone: timeZone)
    }
}
