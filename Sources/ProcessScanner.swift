import Foundation

/// One line of `ps`: process id, parent id, memory (RSS, KB) and executable path.
struct ProcInfo {
    let pid: Int
    let ppid: Int
    let rssKB: Int
    let path: String
    var name: String { (path as NSString).lastPathComponent }
}

enum ProcGroup: String, CaseIterable {
    case app = "Claude app"
    case code = "Claude Code"
    case chrome = "Chrome connector"
    case children = "Started by Claude (MCP servers, shells)"
    case bulb = "claude-bulb"
}

struct ClaudeProcess {
    let info: ProcInfo
    let group: ProcGroup
}

/// Finds Claude's processes. A process counts if it runs from a Claude install, and so does
/// everything it started: MCP servers often show up only as "node".
enum ProcessScanner {
    static func scan() -> [ClaudeProcess] {
        let text = Shell.output("/bin/ps", ["-axo", "pid=,ppid=,rss=,comm="], fixtureEnv: "CLAUDE_BULB_PS")
        return claudeProcesses(parse(text))
    }

    /// The path is last and may contain spaces, so split at most 3 times.
    static func parse(_ text: String) -> [ProcInfo] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard f.count == 4, let pid = Int(f[0]), let ppid = Int(f[1]), let rss = Int(f[2]) else { return nil }
            return ProcInfo(pid: pid, ppid: ppid, rssKB: rss, path: String(f[3]))
        }
    }

    /// Which Claude product a path belongs to, or nil if none. Order matters:
    /// Claude Code inside the app folder is still Claude Code.
    static func group(of path: String) -> ProcGroup? {
        if path.contains("claude-bulb") { return .bulb }
        if path.contains("/Application Support/Claude/claude-code") || path.contains("/.local/share/claude/")
            || path.hasSuffix("/bin/claude") || path == "claude" { return .code }
        if path.contains("/Claude.app/") && path.hasSuffix("/chrome-native-host") { return .chrome }
        if path.contains("/Claude.app/") { return .app }
        return nil
    }

    /// Claude processes plus all their descendants. Time O(P), space O(P) for P processes.
    static func claudeProcesses(_ all: [ProcInfo]) -> [ClaudeProcess] {
        var kids: [Int: [ProcInfo]] = [:]
        for p in all { kids[p.ppid, default: []].append(p) }
        var out: [ClaudeProcess] = []
        var queue = all.compactMap { p in group(of: p.path).map { ClaudeProcess(info: p, group: $0) } }
        var seen = Set(queue.map(\.info.pid))
        while let next = queue.popLast() {
            out.append(next)
            for child in kids[next.info.pid] ?? [] where !seen.contains(child.pid) && child.pid > 1 {
                seen.insert(child.pid)
                queue.append(ClaudeProcess(info: child, group: group(of: child.path) ?? .children))
            }
        }
        return out
    }
}
