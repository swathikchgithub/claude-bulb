import Foundation

/// Handles `claude-bulb on` / `claude-bulb off`, which Claude Code hooks call.
/// Claude Code sends the hook's JSON on stdin; we only need "session_id".
enum HookCommand {
    static func sessionId(fromJSON data: Data) -> String? {
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return obj?["session_id"] as? String
    }

    /// Returns the process exit code. Always 0 for bad input: a broken bulb
    /// must never block or fail a Claude Code hook.
    static func run(_ action: String, store: BulbStore, stdin: Data) -> Int32 {
        let id = sessionId(fromJSON: stdin) ?? "unknown"
        switch action {
        case "on": try? store.markWaiting(id)
        case "off": store.clear(id)
        case "clear-all": store.clearAll()
        default:
            FileHandle.standardError.write("usage: claude-bulb [on|off|clear-all]\n".data(using: .utf8)!)
            return 2
        }
        return 0
    }
}
