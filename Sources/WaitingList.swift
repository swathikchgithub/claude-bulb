import Foundation

/// Turns waiting sessions into readable lines for the menu and `claude-bulb list`.
enum WaitingList {
    static func ago(_ d: Date, now: Date) -> String {
        let s = Int(now.timeIntervalSince(d))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60) min ago" }
        return "\(s / 3600) h ago"
    }

    /// e.g. "orca-platform — needs permission: Bash · 3 min ago"
    static func title(_ w: WaitingSession, now: Date) -> String {
        guard let i = w.info else { return "unknown session \(w.id.prefix(8)) · \(ago(w.modified, now: now))" }
        return "\(i.project ?? String(w.id.prefix(8))) — \(i.reason) · \(ago(i.since, now: now))"
    }

    static func detail(_ w: WaitingSession) -> String? {
        w.info?.message.map { $0.count <= 70 ? $0 : $0.prefix(69) + "…" }
    }

    static func text(_ sessions: [WaitingSession], pruned: [String], now: Date) -> String {
        var out = sessions.isEmpty ? ["Nothing is waiting on you."] : ["Waiting on you (\(sessions.count)):"]
        for w in sessions {
            out.append("  " + title(w, now: now))
            if let d = detail(w) { out.append("      \"\(d)\"") }
            out.append("      session \(w.id)")
        }
        if !pruned.isEmpty { out.append("Removed \(pruned.count) stale: \(pruned.joined(separator: ", "))") }
        return out.joined(separator: "\n")
    }
}
