import Foundation

/// Token and cost totals for one session (or for all of them).
struct UsageTotal {
    var label: String
    var usage = TokenUsage()
    var cost = 0.0
    var unpriced = 0          // replies whose model or speed has no price in prices.json
    var lastActive = Date.distantPast

    mutating func add(_ e: UsageEntry, prices: PriceTable) {
        usage = usage + e.usage
        lastActive = max(lastActive, e.time)
        if !e.fast, let c = prices.cost(model: e.model, usage: e.usage) { cost += c } else { unpriced += 1 }
    }

    /// e.g. "in 2 · write 1.4k · read 118k · out 461 · $0.03"
    var line: String {
        let u = usage
        var s = "in \(Self.compact(u.input)) · write \(Self.compact(u.cacheWrite5m + u.cacheWrite1h))"
            + " · read \(Self.compact(u.cacheRead)) · out \(Self.compact(u.output)) · \(Self.dollars(cost))"
        if unpriced > 0 { s += " (+\(unpriced) unpriced)" }
        return s
    }

    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }

    static func dollars(_ x: Double) -> String {
        x > 0 && x < 0.01 ? "<$0.01" : String(format: "$%.2f", x)
    }
}

/// Today's usage: one total per session plus a grand total.
struct UsageReport {
    let sessions: [UsageTotal]   // most expensive first
    let total: UsageTotal

    /// Time O(L) over all lines in transcripts touched since `since`; space O(R), R = unique replies.
    static func build(root: URL, since: Date, prices: PriceTable) -> UsageReport {
        var total = UsageTotal(label: "Total")
        var sessions: [UsageTotal] = []
        for (sid, files) in UsageReader.transcripts(under: root, modifiedSince: since) {
            var unique: [String: UsageEntry] = [:]   // dedupe: one reply, many lines
            for f in files { for e in UsageReader.entries(in: f, since: since) { unique[e.id] = e } }
            guard !unique.isEmpty else { continue }
            let cwd = unique.values.compactMap(\.cwd).first
            var s = UsageTotal(label: cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? String(sid.prefix(8)))
            for e in unique.values { s.add(e, prices: prices); total.add(e, prices: prices) }
            sessions.append(s)
        }
        return UsageReport(sessions: sessions.sorted { $0.cost > $1.cost }, total: total)
    }

    static func startOfToday() -> Date { Calendar.current.startOfDay(for: Date()) }

    /// Plain-text report for `claude-bulb usage`.
    var text: String {
        let rows = sessions.map { "  \($0.label): \($0.line)" }
        return (["Today, API-equivalent cost (not what a subscription bills):"] + rows
                + ["  \(total.label): \(total.line)"]).joined(separator: "\n")
    }
}
