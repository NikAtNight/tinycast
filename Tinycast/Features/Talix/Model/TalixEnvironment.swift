import Foundation

enum TalixEnvironment: String, Codable, CaseIterable, Sendable {
    case production
    case development

    var endpoint: URL {
        URL(string: self == .production ? "https://api.talix.app/api/mcp" : "https://apidev.talix.app/api/mcp")!
    }

    var title: String { self == .production ? "Production" : "Development" }
}
