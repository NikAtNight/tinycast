import Darwin
import Foundation

enum PortScanner {
    enum Failure: LocalizedError {
        case unavailable
        case scan(String)
        case unsafeGroup
        case signal(Int32)

        var errorDescription: String? {
            switch self {
            case .unavailable: "Couldn't find lsof."
            case .scan(let detail): "Couldn't scan listening ports: \(detail)"
            case .unsafeGroup: "This process group cannot be stopped safely from Tinycast."
            case .signal(let code): "Couldn't stop the process group: \(String(cString: strerror(code)))"
            }
        }
    }

    nonisolated static func scan(executable: URL) async throws -> [ListeningPort] {
        let result = try await ToolRunner.run(
            executable, ["-nP", "-iTCP", "-sTCP:LISTEN", "+c0"], timeout: 5)
        if result.status == 1, result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }
        guard result.succeeded else { throw Failure.scan(result.tail) }
        var ports = LsofParser.parse(result.output)
        var directories: [Int32: String] = [:]
        for pid in Set(ports.map(\.pid)).sorted() {
            try Task.checkCancellation()
            let cwd = try await ToolRunner.run(
                executable, ["-a", "-p", String(pid), "-d", "cwd", "-Fn"], timeout: 5)
            if cwd.succeeded { directories[pid] = LsofParser.parseCwd(cwd.output) }
        }
        for index in ports.indices { ports[index].cwd = directories[ports[index].pid] }
        return ports
    }

    nonisolated static func kill(pid: Int32) async throws {
        guard pid > 1, pid != getpid() else { throw Failure.unsafeGroup }
        let group = getpgid(pid)
        if group == -1, errno == ESRCH { return }
        guard group > 1, group != getpgrp() else { throw Failure.unsafeGroup }
        try signal(group: group, value: SIGTERM)
        try await Task.sleep(for: .seconds(3))
        if Darwin.kill(-group, 0) == 0 || errno == EPERM {
            try signal(group: group, value: SIGKILL)
        }
    }

    nonisolated private static func signal(group: Int32, value: Int32) throws {
        if Darwin.kill(-group, value) != 0, errno != ESRCH {
            throw Failure.signal(errno)
        }
    }
}
