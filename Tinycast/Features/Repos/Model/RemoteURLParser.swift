import Foundation

enum RemoteURLParser {
    struct Remote: Equatable, Sendable {
        let webURL: String
        let org: String
    }

    static func parse(_ raw: String) -> Remote? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: String
        if !value.contains("://"), let colon = value.firstIndex(of: ":") {
            let host = value[..<colon].split(separator: "@").last.map(String.init) ?? ""
            candidate = "https://\(host)/\(value[value.index(after: colon)...])"
        } else {
            candidate = value
        }
        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme, ["https", "http", "ssh", "git"].contains(scheme),
              let host = components.host, host.contains("."), !host.contains(" ") else { return nil }
        var path = components.path
        if path.hasSuffix(".git") { path.removeLast(4) }
        let parts = path.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        components.scheme = "https"
        components.user = nil
        components.password = nil
        components.port = nil
        components.query = nil
        components.fragment = nil
        components.path = "/" + parts.joined(separator: "/")
        guard let webURL = components.url?.absoluteString else { return nil }
        return Remote(webURL: webURL, org: parts.dropLast().joined(separator: "/"))
    }

    static func parseConfig(_ text: String) -> Remote? {
        var isOrigin = false
        for line in text.components(separatedBy: .newlines) {
            let value = line.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("[") {
                isOrigin = value.lowercased() == "[remote \"origin\"]"
            } else if isOrigin, let equals = value.firstIndex(of: "=") {
                let key = value[..<equals].trimmingCharacters(in: .whitespaces)
                if key.lowercased() == "url" {
                    let raw = value[value.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                    return parse(raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
                }
            }
        }
        return nil
    }
}
