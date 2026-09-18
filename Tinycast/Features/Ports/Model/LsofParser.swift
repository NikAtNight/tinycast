import Foundation

enum LsofParser {
    static func parse(_ output: String) -> [ListeningPort] {
        var seen: Set<String> = []
        return output.split(separator: "\n").compactMap { line in
            let columns = line.split(whereSeparator: \.isWhitespace)
            guard columns.count >= 9,
                let pid = Int32(columns[1]), pid > 0,
                columns.contains("TCP")
            else { return nil }
            let address = columns.last == "(LISTEN)" ? columns[columns.count - 2] : columns.last!
            guard let colon = address.lastIndex(of: ":"),
                let port = Int(address[address.index(after: colon)...]), (1...65535).contains(port)
            else { return nil }
            let item = ListeningPort(
                port: port, pid: pid,
                command: String(columns[0]).replacingOccurrences(of: "\\x20", with: " "),
                address: String(address))
            return seen.insert(item.id).inserted ? item : nil
        }
    }

    static func parseCwd(_ output: String) -> String? {
        output.split(separator: "\n").first(where: { $0.hasPrefix("n/") })
            .map { String($0.dropFirst()) }
    }
}
