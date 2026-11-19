import Foundation

/// A launchd job (background service) that belongs to Claude or Anthropic.
struct ServiceInfo {
    let label: String
    let pid: Int?        // nil when loaded but not running right now
    let lastExit: Int?
    let loaded: Bool     // false: a plist is installed but launchd has not loaded it

    var name: String { ServiceScanner.friendlyName(label) }
}

/// Lists Claude's launchd jobs for your user, and any installed plists that are not loaded.
/// System daemons owned by root are only seen through their plist files.
enum ServiceScanner {
    static func scan(_ p: FootprintPaths) -> [ServiceInfo] {
        let loaded = parse(Shell.output("/bin/launchctl", ["list"], fixtureEnv: "CLAUDE_BULB_LAUNCHCTL"))
        let loadedLabels = Set(loaded.map(\.label))
        let extra = installedLabels(p).filter { !loadedLabels.contains($0) }
            .map { ServiceInfo(label: $0, pid: nil, lastExit: nil, loaded: false) }
        return (loaded + extra).sorted { $0.label < $1.label }
    }

    static func isClaude(_ label: String) -> Bool {
        let l = label.lowercased()
        return l.contains("anthropic") || l.contains("claude")
    }

    /// `launchctl list` prints "PID<tab>Status<tab>Label"; PID is "-" when not running.
    static func parse(_ text: String) -> [ServiceInfo] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count == 3, isClaude(String(f[2])), f[0] != "PID" else { return nil }
            return ServiceInfo(label: String(f[2]), pid: Int(f[0]), lastExit: Int(f[1]), loaded: true)
        }
    }

    /// Unique labels: the same plist name in two folders is one service.
    static func installedLabels(_ p: FootprintPaths) -> [String] {
        let dirs = [p.inHome("Library/LaunchAgents"), p.inSystem("Library/LaunchAgents"), p.inSystem("Library/LaunchDaemons")]
        return Set(dirs.map(\.standardizedFileURL)).flatMap { dir in
            ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
                .filter { $0.hasSuffix(".plist") && isClaude($0) }.map { String($0.dropLast(6)) }
        }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    static func friendlyName(_ label: String) -> String {
        if label.hasPrefix("application.com.anthropic.claudefordesktop") { return "Claude app" }
        if label == "com.anthropic.claudefordesktop.ShipIt" { return "Claude auto-updater" }
        if label == "local.claude-bulb" { return "claude-bulb" }
        return label
    }
}
