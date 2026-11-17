import Foundation

/// One Claude reply as recorded in a transcript.
struct UsageEntry {
    let id: String        // message id: the same reply is written on several lines, so we dedupe by it
    let model: String
    let time: Date
    let usage: TokenUsage
    let fast: Bool        // fast mode is billed at a premium we do not price
    let cwd: String?      // the project folder, used as a readable label
}

/// Reads Claude Code transcripts (~/.claude/projects/<project>/<session>.jsonl, and
/// <session>/subagents/*.jsonl). Single responsibility: files in, UsageEntry out. No prices.
enum UsageReader {
    static func defaultRoot() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["CLAUDE_BULB_PROJECTS"] { return URL(fileURLWithPath: dir) }
        let config = env["CLAUDE_CONFIG_DIR"] ?? (NSHomeDirectory() + "/.claude")
        return URL(fileURLWithPath: config).appendingPathComponent("projects")
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// nil for anything that is not an assistant reply with usage (user lines, broken JSON, synthetic).
    static func parse(line: Substring) -> UsageEntry? {
        guard line.contains("\"usage\""),   // cheap filter before JSON parsing
              let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let msg = obj["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any],
              let id = msg["id"] as? String,
              let model = msg["model"] as? String, model != "<synthetic>",
              let stamp = obj["timestamp"] as? String, let time = iso.date(from: stamp) else { return nil }
        return UsageEntry(id: id, model: model, time: time, usage: TokenUsage(json: usage),
                          fast: (usage["speed"] as? String) == "fast", cwd: obj["cwd"] as? String)
    }

    /// Time O(L) for L lines; space O(file size), since the file is read in one go.
    static func entries(in file: URL, since: Date) -> [UsageEntry] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap(parse).filter { $0.time >= since }
    }

    /// Transcripts touched since `since`, grouped under their session id.
    /// A subagent file belongs to the session folder it sits in. Time O(F), F = files under root.
    static func transcripts(under root: URL, modifiedSince since: Date) -> [String: [URL]] {
        var out: [String: [URL]] = [:]
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return out }
        for case let url as URL in walk where url.pathExtension == "jsonl" {
            let modified = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
            guard modified >= since else { continue }
            out[sessionId(of: url), default: []].append(url)
        }
        return out
    }

    static func sessionId(of url: URL) -> String {
        let parent = url.deletingLastPathComponent()
        if parent.lastPathComponent == "subagents" { return parent.deletingLastPathComponent().lastPathComponent }
        return url.deletingPathExtension().lastPathComponent
    }
}
