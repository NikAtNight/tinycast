import Foundation

@main
struct PortsTests {
    nonisolated(unsafe) static var failures = 0

    static let listeners = """
        COMMAND                      PID         USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        Python                     66538 nikhlkapadia    3u  IPv4 0x750ac1906cd85a82      0t0  TCP 127.0.0.1:51347 (LISTEN)
        Python                     66538 nikhlkapadia    4u  IPv6 0xb7dffd330410aa84      0t0  TCP [::1]:51347 (LISTEN)
        """
    static let cwd = """
        p66538
        fcwd
        n/private/var/folders/s7/6ctmdy055ml8vds23sr3qtnc0000gn/T/tinycast ports am9fzccv
        """

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        parsing()
        malformedRows()
        workingDirectory()
        filtering()
        print(failures == 0 ? "Ports tests passed" : "\(failures) ports tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func parsing() {
        let parsed = LsofParser.parse(listeners)
        expect(parsed.count == 1, "IPv4 and IPv6 listeners share one pid and port row")
        expect(parsed.first?.pid == 66538, "the captured process id survives parsing")
        expect(parsed.first?.port == 51347, "the trailing port survives parsing")
        expect(parsed.first?.command == "Python", "the command survives parsing")
        expect(parsed.first?.address == "127.0.0.1:51347", "the first address survives deduplication")
        expect(parsed.first?.cwd == nil, "listener rows have no cwd until enrichment")
        expect(LsofParser.parse("").isEmpty, "empty stdout from lsof exit 1 has no listeners")
        expect(
            LsofParser.parse("COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\n").isEmpty,
            "a header alone has no listeners")
        let variants = """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            node 100 user 3u IPv6 0x1 0t0 TCP *:3000 (LISTEN)
            node 100 user 4u IPv4 0x2 0t0 TCP 127.0.0.1:3001 (LISTEN)
            node 101 user 3u IPv6 0x3 0t0 TCP [::1]:3000 (LISTEN)
            My\\x20Server 102 user 3u IPv4 0x4 0t0 TCP *:8080 (LISTEN)
            """
        let rows = LsofParser.parse(variants)
        expect(rows.count == 4, "deduplication preserves distinct ports and distinct processes")
        expect(
            rows.contains { $0.address == "[::1]:3000" && $0.port == 3000 },
            "IPv6 parsing uses the final colon")
        expect(rows.contains { $0.command == "My Server" }, "lsof escaped command spaces decode")
    }

    static func malformedRows() {
        let output = """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            missing fields
            node nope user 3u IPv4 0x1 0t0 TCP *:3000 (LISTEN)
            node -1 user 3u IPv4 0x1 0t0 TCP *:3000 (LISTEN)
            node 0 user 3u IPv4 0x1 0t0 TCP *:3000 (LISTEN)
            node 99999999999999 user 3u IPv4 0x1 0t0 TCP *:3000 (LISTEN)
            node 100 user 3u IPv4 0x1 0t0 TCP *:http (LISTEN)
            node 100 user 3u IPv4 0x1 0t0 TCP *:0 (LISTEN)
            node 100 user 3u IPv4 0x1 0t0 TCP *:65536 (LISTEN)
            node 100 user 3u IPv4 0x1 0t0 TCP no-address (LISTEN)
            """
        expect(LsofParser.parse(output).isEmpty, "malformed fields and invalid ids or ports are rejected")
    }

    static func workingDirectory() {
        expect(
            LsofParser.parseCwd(cwd)
                == "/private/var/folders/s7/6ctmdy055ml8vds23sr3qtnc0000gn/T/tinycast ports am9fzccv",
            "captured cwd spaces survive field parsing")
        expect(LsofParser.parseCwd("") == nil, "empty cwd output has no path")
        expect(LsofParser.parseCwd("p100\nfcwd\n") == nil, "missing name field has no path")
        expect(LsofParser.parseCwd("p100\nfcwd\nn\n") == nil, "empty name field has no path")
    }

    static func filtering() {
        let rows = [
            ListeningPort(
                port: 3011, pid: 100, command: "node", address: "*:3011",
                cwd: "/Users/test/Work/sxcl-frontend-app"),
            ListeningPort(
                port: 8080, pid: 101, command: "Python", address: "127.0.0.1:8080",
                cwd: "/Users/test/Work/Project With Spaces"),
            ListeningPort(port: 5432, pid: 102, command: "postgres", address: "[::1]:5432")
        ]
        expect(PortsQuery.rank(rows, for: "").count == rows.count, "blank query lists every listener")
        expect(
            PortsQuery.rank(rows, for: " \t\n ").count == rows.count,
            "whitespace query lists every listener")
        expect(PortsQuery.rank(rows, for: "3011").map(\.pid) == [100], "port numbers are searchable")
        expect(PortsQuery.rank(rows, for: "PYTHON").map(\.pid) == [101], "commands ignore case")
        expect(PortsQuery.rank(rows, for: "sxcl").map(\.pid) == [100], "cwd basename is searchable")
        expect(PortsQuery.rank(rows, for: "ptgrs").map(\.pid) == [102], "commands allow fuzzy matching")
        expect(PortsQuery.rank(rows, for: "spaces").map(\.pid) == [101], "cwd words are searchable")
        expect(PortsQuery.rank(rows, for: "zzzzzz").isEmpty, "unmatched queries have no rows")
        expect(PortsQuery.rank([], for: "node").isEmpty, "an empty scan stays empty under a query")
    }
}
