import Foundation

enum TalixRPC {
    struct Projects: Decodable, Sendable {
        let projects: [TalixProject]
    }

    struct Entries: Decodable, Sendable {
        let projectId: String
        let total: Int
        let items: [TalixTimeEntry]
    }

    struct Created: Decodable, Sendable {
        let item: TalixTimeEntry
    }

    enum RPCError: String, LocalizedError {
        case malformed = "Talix returned an unreadable response."
        case rejected = "Talix rejected the request. Check your access and entry details."
        case oversized = "The Talix request exceeds 64 KiB. Shorten the description."
        var errorDescription: String? { rawValue }
    }

    static func projects(id: Int, search: String? = nil) throws -> Data {
        try call(id: id, tool: "list_projects", arguments: search.map { ["search": $0] } ?? [:])
    }

    static func entries(id: Int, projectId: String, startDate: String, endDate: String,
                        offset: Int = 0, limit: Int = 100) throws -> Data {
        try call(id: id, tool: "list_time_entries", arguments: [
            "projectId": projectId, "startDate": startDate, "endDate": endDate,
            "offset": offset, "limit": limit
        ])
    }

    static func report(id: Int, startDate: String, endDate: String,
                       projectId: String? = nil, team: Bool = false) throws -> Data {
        var arguments: [String: Any] = [
            "startDate": startDate, "endDate": endDate, "scope": team ? "team" : "individual"
        ]
        if let projectId { arguments["projectId"] = projectId }
        return try call(id: id, tool: "get_report", arguments: arguments)
    }

    static func create(id: Int, projectId: String, entry: TalixTimeEntry) throws -> Data {
        try write(id: id, tool: "create_time_entry", projectId: projectId, entryId: nil, entry: entry)
    }

    static func update(id: Int, projectId: String, entryId: String, entry: TalixTimeEntry) throws -> Data {
        try write(id: id, tool: "update_time_entry", projectId: projectId, entryId: entryId, entry: entry)
    }

    private static func write(id: Int, tool: String, projectId: String,
                              entryId: String?, entry: TalixTimeEntry) throws -> Data {
        guard let start = entry.startTime, let end = entry.endTime,
            let startDate = TalixTimeEntry.timestamp(start), let endDate = TalixTimeEntry.timestamp(end),
            endDate > startDate, entry.date == String(start.prefix(10))
        else { throw TalixEntryDraft.DraftError.invalidInterval }
        guard entry.rate.isFinite, entry.rate >= 0 else { throw TalixEntryDraft.DraftError.invalidRate }
        guard !entry.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            entry.description.utf16.count <= 2000 else { throw TalixEntryDraft.DraftError.invalidDescription }
        var arguments: [String: Any] = [
            "projectId": projectId, "description": entry.description, "date": entry.date,
            "startTime": start, "endTime": end, "rate": entry.rate, "billable": entry.billable
        ]
        if let entryId { arguments["entryId"] = entryId }
        return try call(id: id, tool: tool, arguments: arguments)
    }

    private static func call(id: Int, tool: String, arguments: [String: Any]) throws -> Data {
        let data = try MCPProtocol.request(id: id, method: "tools/call", params: [
            "name": tool, "arguments": arguments
        ])
        guard data.count <= 65536 else { throw RPCError.oversized }
        return data
    }

    static func payload(_ data: Data, id: Int) throws -> Data {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["jsonrpc"] as? String == "2.0", object["id"] as? Int == id
        else { throw RPCError.malformed }
        guard object["error"] == nil else { throw RPCError.rejected }
        guard let result = object["result"] as? [String: Any] else { throw RPCError.malformed }
        guard result["isError"] as? Bool != true else { throw RPCError.rejected }
        if let structured = result["structuredContent"] {
            return try JSONSerialization.data(withJSONObject: structured)
        }
        guard let content = result["content"] as? [[String: Any]],
            let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String
        else { throw RPCError.malformed }
        return Data(text.utf8)
    }
}
