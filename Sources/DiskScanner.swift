import Foundation

/// Where to look. Normally your home folder and "/". CLAUDE_BULB_HOME points both at a
/// fake folder so tests never read your real disk.
struct FootprintPaths {
    let home: URL
    let system: URL

    static func current() -> FootprintPaths {
        if let fake = ProcessInfo.processInfo.environment["CLAUDE_BULB_HOME"] {
            let u = URL(fileURLWithPath: fake)
            return FootprintPaths(home: u, system: u)
        }
        return FootprintPaths(home: URL(fileURLWithPath: NSHomeDirectory()), system: URL(fileURLWithPath: "/"))
    }

    func inHome(_ p: String) -> URL { home.appendingPathComponent(p) }
    func inSystem(_ p: String) -> URL { system.appendingPathComponent(p) }

    /// "~/Library/..." instead of the full home path.
    func display(_ url: URL) -> String {
        let path = url.path, h = home.path
        return path.hasPrefix(h + "/") ? "~" + path.dropFirst(h.count) : path
    }
}

/// One place on disk that Claude uses, with its biggest sub-folders.
struct DiskItem {
    let label: String
    let url: URL
    let bytes: Int64
    let parts: [(name: String, bytes: Int64)]   // top 3 children of at least 1 MB, smaller than the whole
}

/// Finds and sizes Claude's folders. Read-only: it never deletes or moves anything.
enum DiskScanner {
    static func knownLocations(_ p: FootprintPaths) -> [(String, URL)] {
        [("Claude app data", p.inHome("Library/Application Support/Claude")),
         ("Claude app", p.inSystem("Applications/Claude.app")),
         ("Claude Code install", p.inHome(".local/share/claude")),
         ("Claude Code transcripts, settings, plugins", p.inHome(".claude")),
         ("Claude Code config file", p.inHome(".claude.json")),
         ("Claude Code cache", p.inHome("Library/Caches/claude-cli-nodejs")),
         ("Claude Code state", p.inHome(".local/state/claude")),
         ("Claude Code cache (XDG)", p.inHome(".cache/claude")),
         ("Claude app cache", p.inHome("Library/Caches/com.anthropic.claudefordesktop")),
         ("Claude updater cache", p.inHome("Library/Caches/com.anthropic.claudefordesktop.ShipIt")),
         ("Claude app logs", p.inHome("Library/Logs/Claude")),
         ("Claude app web storage", p.inHome("Library/HTTPStorages/com.anthropic.claudefordesktop")),
         ("Claude app preferences", p.inHome("Library/Preferences/com.anthropic.claudefordesktop.plist")),
         ("Anthropic CLI login", p.inHome(".config/anthropic")),
         ("Chrome connector manifest (Claude)",
          p.inHome("Library/Application Support/Google/Chrome/NativeMessagingHosts/com.anthropic.claude_browser_extension.json")),
         ("Chrome connector manifest (Claude Code)",
          p.inHome("Library/Application Support/Google/Chrome/NativeMessagingHosts/com.anthropic.claude_code_browser_extension.json")),
         ("claude-bulb state", p.inHome(".claude-bulb")),
         ("Claude temp files", p.inSystem("private/tmp/claude-\(getuid())"))]
    }

    /// Usual folders where apps keep files; anything inside named claude/anthropic is reported too.
    static let searchDirs = ["Library/Application Support", "Library/Caches", "Library/Logs", "Library/Preferences",
                             "Library/HTTPStorages", "Library/Saved Application State", "Library/WebKit",
                             "Library/Application Support/Google/Chrome/NativeMessagingHosts",
                             ".config", ".local/share", ".local/state", ".cache"]

    static func isClaudeName(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("claude") || n.contains("anthropic")
    }

    /// Time O(D) for D entries directly inside the search folders.
    static func discovered(_ p: FootprintPaths, known: [URL]) -> [(String, URL)] {
        let knownPaths = known.map(\.standardizedFileURL.path)
        func covered(_ u: URL) -> Bool {
            let path = u.standardizedFileURL.path
            return knownPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
        return searchDirs.flatMap { dir -> [(String, URL)] in
            let base = p.inHome(dir)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
            return names.filter(isClaudeName).map { base.appendingPathComponent($0) }
                .filter { !covered($0) }.map { ("Other: \($0.lastPathComponent)", $0) }
        }
    }

    /// All locations that exist, biggest first. Time O(F) for F files under them.
    static func scan(_ p: FootprintPaths) -> [DiskItem] {
        let known = knownLocations(p)
        let all = known + discovered(p, known: known.map(\.1))
        return all.compactMap { item(label: $0.0, url: $0.1) }.sorted { $0.bytes > $1.bytes }
    }

    static func item(label: String, url: URL) -> DiskItem? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        guard isDir.boolValue else { return DiskItem(label: label, url: url, bytes: fileSize(url), parts: []) }
        let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        let sized = children.map { (name: $0.lastPathComponent, bytes: allocatedSize($0)) }
        let total = sized.reduce(0) { $0 + $1.bytes }
        // A part that is almost the whole folder (e.g. Claude.app/Contents) tells you nothing: skip it.
        let parts = sized.filter { $0.bytes >= 1_000_000 && Double($0.bytes) < Double(total) * 0.99 }
            .sorted { $0.bytes > $1.bytes }.prefix(3)
        return DiskItem(label: label, url: url, bytes: total, parts: Array(parts))
    }

    /// Space the file really takes on disk (like Finder), not its logical length.
    static func fileSize(_ url: URL) -> Int64 {
        let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
    }

    /// Sum over every regular file inside. Symlinks are not followed, so nothing is counted twice through a link.
    static func allocatedSize(_ url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        guard isDir.boolValue else { return fileSize(url) }
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let walk = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys,
                                                        errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in walk {
            guard let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }
}
