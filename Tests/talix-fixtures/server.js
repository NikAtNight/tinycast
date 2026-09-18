import http from "node:http";
import fs from "node:fs";

const projects = JSON.parse(fs.readFileSync(new URL("projects.json", import.meta.url)));
const entries = JSON.parse(fs.readFileSync(new URL("entries.json", import.meta.url)));
const sessions = new Set();
const writes = new Map();
let dropped = false;
const server = http.createServer(async (req, res) => {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const body = Buffer.concat(chunks);
    if (req.method !== "POST" || body.length > 65536 || req.headers.origin ||
        req.headers.authorization !== "Bearer tlx_fixture" ||
        req.headers["content-type"] !== "application/json" ||
        !req.headers.accept.includes("text/event-stream") ||
        req.headers["mcp-protocol-version"] !== "2025-06-18") {
        res.writeHead(400).end(); return;
    }
    if (req.url === "/unauthorized") { res.writeHead(401).end(); return; }
    const message = JSON.parse(body);
    const { id, method, params } = message;
    if (method !== "tools/call") { res.writeHead(400).end(); return; }
    const session = req.headers["mcp-session-id"];
    if (sessions.has(req.url) && req.url !== "/drop" && session !== "fixture-session") { res.writeHead(400).end(); return; }
    sessions.add(req.url);
    let payload;
    const args = params.arguments;
    switch (params.name) {
    case "list_projects": payload = projects; break;
    case "list_time_entries":
        payload = { ...entries, projectId: args.projectId, items: entries.items.slice(args.offset, args.offset + 1) };
        break;
    case "create_time_entry":
    case "update_time_entry": {
        if (args.entry || !args.projectId || !args.description || typeof args.rate !== "number" ||
            typeof args.billable !== "boolean" || args.date !== args.startTime?.slice(0, 10) ||
            Date.parse(args.endTime) <= Date.parse(args.startTime)) {
            res.writeHead(422).end(); return;
        }
        const key = `${args.projectId}|${args.startTime}|${args.endTime}`;
        if (!writes.has(key)) writes.set(key, { ...args, id: `saved-${writes.size}`, rate: String(args.rate) });
        payload = { item: writes.get(key) };
        if (req.url === "/drop" && !dropped) { dropped = true; req.socket.destroy(); return; }
        break;
    }
    case "get_report": payload = { reports: [], scope: args.scope }; break;
    default: res.writeHead(400).end(); return;
    }
    let response = { jsonrpc: "2.0", id, result: { content: [{ type: "text", text: JSON.stringify(payload) }] } };
    if (req.url === "/error") response.result = { isError: true, content: [{ type: "text", text: "denied" }] };
    if (req.url === "/mismatch") response.id = id + 1;
    if (req.url === "/rpc-error") response = { jsonrpc: "2.0", id, error: { code: -32603, message: "failed" } };
    res.setHeader("Mcp-Session-Id", "fixture-session");
    if (req.url === "/sse") {
        res.setHeader("Content-Type", "text/event-stream");
        res.end(`event: message\ndata: ${JSON.stringify(response)}\n\n`);
    } else {
        res.setHeader("Content-Type", "application/json");
        res.end(req.url === "/invalid" ? "{" : JSON.stringify(response));
    }
});
server.listen(0, "127.0.0.1", () => process.stdout.write(String(server.address().port) + "\n"));
process.on("SIGTERM", () => server.close(() => process.exit()));
