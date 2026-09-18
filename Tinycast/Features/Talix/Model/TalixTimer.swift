import Foundation

struct TalixTimer: Codable, Sendable, Equatable {
    enum Rounding: Int, Codable, CaseIterable, Sendable {
        case none = 0
        case sixMinutes = 6
        case fifteenMinutes = 15

        func duration(_ seconds: TimeInterval) -> TimeInterval {
            guard self != .none else { return seconds }
            let step = Double(rawValue * 60)
            return ceil(seconds / step) * step
        }
    }

    let projectId: String
    let projectName: String
    var description: String
    let startedAt: Date

    func entry(
        endingAt: Date, rate: Double, calendar: Calendar, timeZone: TimeZone,
        rounding: Rounding = .none, billable: Bool = true
    ) throws -> TalixTimeEntry {
        guard endingAt > startedAt else { throw TalixEntryDraft.DraftError.invalidInterval }
        let elapsed = rounding.duration(endingAt.timeIntervalSince(startedAt))
        return try TalixTimeEntry(
            description: description, start: startedAt, end: startedAt.addingTimeInterval(elapsed),
            rate: rate, billable: billable, timeZone: timeZone)
    }
}
