import Foundation

/// Handles `claude-bulb on` / `claude-bulb off`, which Claude Code hooks call.
/// Claude Code sends the hook's JSON on stdin: session_id, cwd, transcript_path, hook_event_name,
/// plus tool_name (PermissionRequest), message / notification_type (Notification),
/// last_assistant_message (Stop).
enum HookCommand {
    static func object(fromJSON data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    static func sessionId(fromJSON data: Data) -> String? {
        object(fromJSON: data)["session_id"] as? String
    }

    /// Why Claude is waiting, in plain words.
    static func reason(_ o: [String: Any]) -> String {
        switch o["hook_event_name"] as? String {
        case "PermissionRequest":
            let tool = o["tool_name"] as? String ?? "a tool"
            return tool == "AskUserQuestion" ? "asked you a question" : "needs permission: \(tool)"
        case "Notification":
            switch o["notification_type"] as? String {
            case "permission_prompt": return "needs permission"
            case "idle_prompt": return "waiting for your reply"
            case "elicitation_dialog", "elicitation_url_dialog": return "an MCP server asks for input"
            case let other?: return other
            case nil: return "sent a notification"
            }
        case "Stop": return "finished its turn"
        case let other?: return other
        case nil: return "waiting"
        }
    }

    static func short(_ s: String?, _ max: Int = 120) -> String? {
        guard let t = s?.split(whereSeparator: \.isNewline).first.map(String.init), !t.isEmpty else { return nil }
        return t.count <= max ? t : t.prefix(max - 1) + "…"
    }

    /// Merges with what is already saved: a Notification keeps the more specific earlier reason
    /// (e.g. "needs permission: Bash") and the original start time is kept for every event.
    static func waitInfo(_ o: [String: Any], previous: WaitInfo?, now: Date) -> WaitInfo {
        let isNotification = o["hook_event_name"] as? String == "Notification"
        let text = short(o["message"] as? String) ?? short(o["last_assistant_message"] as? String)
        return WaitInfo(project: (o["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? previous?.project,
                        reason: isNotification && previous != nil ? previous!.reason : reason(o),
                        message: text ?? previous?.message,
                        since: previous?.since ?? now,
                        transcriptPath: o["transcript_path"] as? String ?? previous?.transcriptPath)
    }

    /// Returns the process exit code. Always 0 for bad input: a broken bulb
    /// must never block or fail a Claude Code hook.
    static func run(_ action: String, store: BulbStore, stdin: Data, now: Date = Date()) -> Int32 {
        let o = object(fromJSON: stdin)
        let id = o["session_id"] as? String ?? "unknown"
        switch action {
        case "on": try? store.markWaiting(id, info: waitInfo(o, previous: store.entry(id)?.info, now: now))
        case "off": store.clear(id)
        case "clear-all": store.clearAll()
        default:
            FileHandle.standardError.write("usage: claude-bulb [on|off|clear-all|list|usage [--since YYYY-MM-DD]|footprint]\n".data(using: .utf8)!)
            return 2
        }
        return 0
    }
}
