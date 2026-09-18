import Foundation

struct TalixTimeEntry: Codable, Sendable, Equatable {
    var id: String?
    let description: String
    let date: String
    let startTime: String?
    let endTime: String?
    let rate: Double
    let billable: Bool
    var durationHours: Double?

    enum CodingKeys: String, CodingKey {
        case id, description, date, startTime, endTime, rate, billable
        case durationHours = "duration"
    }

    init(
        description: String, start: Date, end: Date, rate: Double, billable: Bool,
        timeZone: TimeZone
    ) throws {
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty, description.utf16.count <= 2000 else {
            throw TalixEntryDraft.DraftError.invalidDescription
        }
        guard rate.isFinite, rate >= 0 else { throw TalixEntryDraft.DraftError.invalidRate }
        guard end > start else { throw TalixEntryDraft.DraftError.invalidInterval }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        startTime = formatter.string(from: start)
        endTime = formatter.string(from: end)
        guard startTime != endTime else { throw TalixEntryDraft.DraftError.invalidInterval }
        date = String(formatter.string(from: start).prefix(10))
        self.description = description
        self.rate = rate
        self.billable = billable
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id)
        description = try values.decode(String.self, forKey: .description)
        date = try values.decode(String.self, forKey: .date)
        startTime = try values.decodeIfPresent(String.self, forKey: .startTime)
        endTime = try values.decodeIfPresent(String.self, forKey: .endTime)
        billable = try values.decode(Bool.self, forKey: .billable)
        durationHours = (try? values.decode(Double.self, forKey: .durationHours))
            ?? (try? values.decode(String.self, forKey: .durationHours)).flatMap(Double.init)
        guard durationHours.map({ $0.isFinite && $0 >= 0 && $0 < 1_000_000 }) ?? true else {
            throw TalixRPC.RPCError.malformed
        }
        if let number = try? values.decode(Double.self, forKey: .rate) {
            guard number.isFinite, number >= 0 else { throw TalixEntryDraft.DraftError.invalidRate }
            rate = number
        } else {
            let string = try values.decode(String.self, forKey: .rate)
            guard let number = Double(string), number.isFinite, number >= 0 else {
                throw TalixEntryDraft.DraftError.invalidRate
            }
            rate = number
        }
    }

    var duration: TimeInterval {
        guard let startTime, let endTime,
            let start = Self.timestamp(startTime), let end = Self.timestamp(endTime)
        else { return max(0, durationHours ?? 0) * 3600 }
        return max(0, end.timeIntervalSince(start))
    }

    static func timestamp(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    static func durationLabel(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "Unknown duration" }
        let minutes = Int(seconds / 60)
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
