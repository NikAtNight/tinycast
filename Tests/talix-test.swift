import Foundation

@main
struct TalixTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func rejects(_ name: String, _ action: () throws -> Void) {
        do { try action(); fatalError("Accepted invalid input: \(name)") } catch {}
    }

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: "Tests/talix-fixtures/\(name).json"))
    }

    @MainActor static func main() async throws {
        let zone = TimeZone(identifier: "America/Toronto")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let now = TalixTimeEntry.timestamp("2026-09-18T16:45:30-04:00")!
        func parse(_ text: String, at date: Date? = nil, rounding: TalixTimer.Rounding = .none) throws -> TalixEntryDraft {
            try TalixEntryDraft.parse(text, now: date ?? now, calendar: calendar, timeZone: zone, rounding: rounding)
        }
        for input in ["1.5", "1h30", "1h30m", "90m", "  1.5  ", "1H30"] {
            let draft = try parse(input)
            check(draft.end.timeIntervalSince(draft.start) == 5400, input)
            check(draft.end == now, "Duration ends at injected now")
        }
        for (input, seconds) in [("1h", 3600.0), ("0.5", 1800), ("1m", 60), ("24", 86400), ("0h01", 60)] {
            let draft = try parse(input)
            check(draft.end.timeIntervalSince(draft.start) == seconds, input)
        }
        for input in ["", "0", "-1", "1e3", "nan", "inf", "1,5", ".5", "1h60", "1h90", "90", "1441m",
                      "1.5h", "1m30", "1h-2", "today", "1h next mon", "1h nope", "9-9", "11-9", "24-25",
                      "9:60-11", "9:-11", "9-11-12", "-9-11", "9-", "9-11 mondayx"] {
            rejects(input) { _ = try parse(input) }
        }
        for (word, day) in [("today", 18), ("yesterday", 17), ("mon", 14), ("monday", 14), ("tue", 15),
                            ("tuesday", 15), ("wed", 16), ("wednesday", 16), ("thu", 17), ("thursday", 17),
                            ("fri", 18), ("friday", 18), ("sat", 12), ("saturday", 12), ("sun", 13), ("sunday", 13)] {
            let draft = try parse("9-11 \(word)")
            check(calendar.component(.day, from: draft.start) == day, word)
            check(calendar.component(.hour, from: draft.start) == 9, "Clock start")
            check(draft.end.timeIntervalSince(draft.start) == 7200, "Clock duration")
            let duration = try parse("90m \(word)")
            check(calendar.component(.day, from: duration.end) == day, "Duration day: \(word)")
        }
        let minutes = try parse("9:15-11:45")
        check(minutes.end.timeIntervalSince(minutes.start) == 9000, "Clock minutes")
        let midnight = TalixTimeEntry.timestamp("2026-01-01T00:30:00-05:00")!
        let crossed = try parse("1h yesterday", at: midnight)
        check(calendar.component(.day, from: crossed.start) == 30, "Duration crosses local midnight")
        let spring = TalixTimeEntry.timestamp("2026-03-08T12:00:00-04:00")!
        rejects("DST gap") { _ = try parse("2:30-4", at: spring) }
        let dst = try parse("1-4", at: spring)
        check(dst.end.timeIntervalSince(dst.start) == 7200, "DST elapsed time")
        let fall = TalixTimeEntry.timestamp("2026-11-01T12:00:00-05:00")!
        let repeated = try parse("1-3", at: fall)
        check(repeated.end.timeIntervalSince(repeated.start) == 10800, "First occurrence of repeated hour")
        for (rounding, seconds) in [(TalixTimer.Rounding.none, 60.0), (.sixMinutes, 360), (.fifteenMinutes, 900)] {
            let draft = try parse("1m", rounding: rounding)
            check(draft.end.timeIntervalSince(draft.start) == seconds, "Draft rounding")
            let timer = TalixTimer(projectId: "alpha", projectName: "Alpha", description: "Work", startedAt: now)
            let entry = try timer.entry(endingAt: now.addingTimeInterval(60), rate: 125.5,
                                       calendar: calendar, timeZone: zone, rounding: rounding, billable: false)
            check(entry.duration == seconds && !entry.billable, "Timer rounding and billable")
            check(entry.date == "2026-09-18" && entry.startTime?.hasSuffix("-04:00") == true, "Local offset")
            rejects("Backwards timer") {
                _ = try timer.entry(endingAt: now, rate: 1, calendar: calendar, timeZone: zone)
            }
        }
        let entry = try minutes.entry(description: " Work ", rate: 0, billable: true, timeZone: zone)
        check(entry.description == "Work", "Trim description")
        for rate in [-1.0, .infinity, .nan] {
            rejects("Rate") { _ = try minutes.entry(description: "Work", rate: rate, billable: true, timeZone: zone) }
        }
        for description in ["", "   ", String(repeating: "a", count: 2001)] {
            rejects("Description") { _ = try minutes.entry(description: description, rate: 1, billable: true, timeZone: zone) }
        }
        _ = try minutes.entry(description: String(repeating: "a", count: 2000), rate: 1, billable: true, timeZone: zone)
        try encoding(entry)
        let projects = try JSONDecoder().decode(TalixRPC.Projects.self, from: fixture("projects"))
        check(projects.projects.count == 2 && projects.projects[0].rate == nil, "Projects without rates")
        let rated = try JSONDecoder().decode(TalixProject.self, from: Data(#"{"id":"a","name":"A","rate":"42.5"}"#.utf8))
        check(rated.rate == 42.5, "Optional decimal project rate")
        let entries = try JSONDecoder().decode(TalixRPC.Entries.self, from: fixture("entries"))
        check(entries.items[0].rate == 125.5 && entries.items[0].duration == 5400, "Decimal and milliseconds")
        check(entries.items[1].duration == 1800, "Entry without timestamps")
        for bad in ["inf", "nan", "100000000000000000000000", "-1"] {
            let data = try JSONSerialization.data(withJSONObject: [
                "description": "Work", "date": "2026-09-18", "rate": 0, "billable": true, "duration": bad
            ])
            rejects("Invalid response duration") { _ = try JSONDecoder().decode(TalixTimeEntry.self, from: data) }
        }
        check(TalixTimeEntry.durationLabel(.infinity) == "Unknown duration", "Safe duration formatting")
        try await transport(entry: entry)
        try await persistence(now: now, entry: entry)
        print("Talix parser, timer, RPC, HTTP stub and persistence checks passed")
    }

    static func encoding(_ entry: TalixTimeEntry) throws {
        func object(_ data: Data) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        }
        let calls = [
            try TalixRPC.projects(id: 1, search: "Alpha"),
            try TalixRPC.entries(id: 2, projectId: "alpha", startDate: "2026-09-18", endDate: "2026-09-18", offset: 10),
            try TalixRPC.report(id: 3, startDate: "2026-09-18", endDate: "2026-09-18", projectId: "alpha", team: true),
            try TalixRPC.create(id: 4, projectId: "alpha", entry: entry),
            try TalixRPC.update(id: 5, projectId: "alpha", entryId: "entry-a", entry: entry)
        ]
        let names = ["list_projects", "list_time_entries", "get_report", "create_time_entry", "update_time_entry"]
        for (index, data) in calls.enumerated() {
            let request = try object(data)
            check(request["method"] as? String == "tools/call" && request["id"] as? Int == index + 1, "RPC envelope")
            let params = request["params"] as? [String: Any] ?? [:]
            check(params["name"] as? String == names[index], "Tool name")
            let args = params["arguments"] as? [String: Any] ?? [:]
            if index >= 3 {
                check(args["entry"] == nil && args["description"] as? String == "Work", "Flat write fields")
                check(args["rate"] as? Double == 0 && args["billable"] as? Bool == true, "Write types")
                check(args["id"] == nil && args["duration"] == nil, "No response-only fields")
            }
            if index == 1 { check(args["offset"] as? Int == 10 && args["limit"] as? Int == 100, "Pagination") }
            if index == 2 { check(args["scope"] as? String == "team", "Report scope") }
            if index == 4 { check(args["entryId"] as? String == "entry-a", "Update ID") }
        }
        rejects("Tool error") {
            _ = try TalixRPC.payload(Data(#"{"jsonrpc":"2.0","id":1,"result":{"isError":true}}"#.utf8), id: 1)
        }
    }

    @MainActor static func transport(entry: TalixTimeEntry) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "Tests/talix-fixtures/server.js"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        let portData = pipe.fileHandleForReading.availableData
        let portText = (String(data: portData, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(portText) else {
            fatalError("Stub did not report port")
        }
        func client(_ route: String, key: String = "tlx_fixture") -> TalixClient {
            TalixClient(endpoint: URL(string: "http://127.0.0.1:\(port)/\(route)")!, key: { key })
        }
        for route in ["json", "sse"] {
            let client = client(route)
            let projects = try await client.projects()
            check(projects.count == 2, "HTTP projects")
            let entries = try await client.entries(projectId: "alpha", day: "2026-09-18")
            check(entries.count == 2, "HTTP pagination and session replay")
            let created = try await client.create(projectId: "alpha", entry: entry)
            let repeated = try await client.create(projectId: "alpha", entry: entry)
            check(created.id == repeated.id && created.rate == 0, "Idempotent retry")
        }
        let dropping = client("drop")
        do { _ = try await dropping.create(projectId: "alpha", entry: entry) } catch {}
        let recovered = try await dropping.create(projectId: "alpha", entry: entry)
        check(recovered.startTime == entry.startTime && recovered.endTime == entry.endTime,
              "Retry exact interval after lost response")
        for route in ["unauthorized", "error", "rpc-error", "invalid", "mismatch"] {
            do { _ = try await client(route).projects(); fatalError("Accepted \(route)") } catch {}
        }
        do { _ = try await client("missing", key: "").projects(); fatalError("Accepted empty key") } catch {}
    }

    @MainActor static func persistence(now: Date, entry: TalixTimeEntry) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("cache.json")
        let timerURL = root.appendingPathComponent("timer.json")
        let store = TalixStore(cacheURL: cache, timerURL: timerURL)
        await store.restore()
        let timer = TalixTimer(projectId: "alpha", projectName: "Alpha", description: "Work", startedAt: now)
        try await store.setRunning(.init(environment: .development, timer: timer, pendingEntry: entry, rate: 125, billable: true))
        let reopened = TalixStore(cacheURL: cache, timerURL: timerURL)
        await reopened.restore()
        check(reopened.running?.timer == timer && reopened.running?.pendingEntry == entry, "Crash recovery preserves exact entry")
        check(reopened.running?.environment == .development, "Timer environment persists")
        check(reopened.running?.rate == 125 && reopened.running?.billable == true, "Timer billing survives restart")
        try Data("cached".utf8).write(to: cache)
        try await reopened.invalidateProjects()
        check(!FileManager.default.fileExists(atPath: cache.path), "Key replacement removes project cache")
        try await reopened.setRunning(nil)
        check(!FileManager.default.fileExists(atPath: timerURL.path), "Discard removes timer")
        try Data("broken".utf8).write(to: timerURL)
        let corrupt = TalixStore(cacheURL: cache, timerURL: timerURL)
        await corrupt.restore()
        check(!corrupt.isReady && corrupt.errorMessage != nil, "Corrupt timer blocks overwrite")
    }
}
