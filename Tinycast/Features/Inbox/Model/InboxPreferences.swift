import Foundation

struct InboxPreferences: Codable, Sendable {
    enum ValidationError: LocalizedError {
        case invalidOrganization
        var errorDescription: String? { "Use GitHub owner names with letters, numbers, and hyphens." }
    }

    var organizations = ["NikAtNight", "dev-talix", "ServiceXcelerator", "olivehq"]
    var refreshMinutes = 5
    var readThrough: [String: Date] = [:]

    static func organizations(from text: String) throws -> [String] {
        let names = text.split { $0 == "," || $0.isWhitespace }.map(String.init)
        guard names.allSatisfy({ name in
            !name.hasPrefix("-") && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }) else { throw ValidationError.invalidOrganization }
        var seen: Set<String> = []
        return names.filter { seen.insert($0.lowercased()).inserted }
    }
}
