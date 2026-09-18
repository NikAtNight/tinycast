import Foundation

struct ListeningPort: Identifiable, Equatable, Sendable {
    let port: Int
    let pid: Int32
    let command: String
    let address: String
    var cwd: String?

    var id: String { "\(pid):\(port)" }
    var directoryName: String? { cwd.map { ($0 as NSString).lastPathComponent } }
}
