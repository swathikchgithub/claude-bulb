import Foundation

/// What the bulb knows about one waiting session. The hook writes it as JSON into the session's file.
struct WaitInfo: Codable, Equatable {
    var project: String?         // last folder of the session's cwd, e.g. "orca-platform"
    var reason: String           // e.g. "needs permission: Bash", "finished its turn"
    var message: String?         // Claude's notification text, or the start of its last reply
    var since: Date              // when this wait started
    var transcriptPath: String?
}

/// One waiting session. `info` is nil for files written by older versions (empty files).
struct WaitingSession {
    let id: String
    let info: WaitInfo?
    let modified: Date           // last time a hook touched it
}

/// Owns the on-disk state: one file per Claude session that is waiting on you.
/// Single responsibility: create, read, delete and prune those files. No UI, no sound.
struct BulbStore {
    let dir: URL
    static let maxAge: TimeInterval = 12 * 3600

    static func defaultStore() -> BulbStore {
        let env = ProcessInfo.processInfo.environment["CLAUDE_BULB_DIR"]
        let path = env ?? (NSHomeDirectory() + "/.claude-bulb/state")
        return BulbStore(dir: URL(fileURLWithPath: path, isDirectory: true))
    }

    /// Only letters, digits, "-" and "_" are allowed, so a session id can never
    /// become a path like "../../something" (path traversal defense).
    static func isSafeId(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128 &&
            id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
    }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    func markWaiting(_ sessionId: String, info: WaitInfo? = nil) throws {
        guard BulbStore.isSafeId(sessionId) else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = info.flatMap { try? BulbStore.encoder.encode($0) }
        FileManager.default.createFile(atPath: dir.appendingPathComponent(sessionId).path, contents: data)
    }

    func clear(_ sessionId: String) {
        guard BulbStore.isSafeId(sessionId) else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(sessionId))
    }

    func clearAll() {
        for name in waitingSessions() { clear(name) }
    }

    /// Time O(n), space O(n), where n = number of waiting sessions (usually 0 to 3).
    func waitingSessions() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { BulbStore.isSafeId($0) }
    }

    func entry(_ id: String) -> WaitingSession? {
        guard BulbStore.isSafeId(id) else { return nil }
        let url = dir.appendingPathComponent(id)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let info = (try? Data(contentsOf: url)).flatMap { try? BulbStore.decoder.decode(WaitInfo.self, from: $0) }
        return WaitingSession(id: id, info: info, modified: attrs[.modificationDate] as? Date ?? .distantPast)
    }

    /// Oldest wait first. Time O(n).
    func entries() -> [WaitingSession] {
        waitingSessions().compactMap(entry).sorted { ($0.info?.since ?? $0.modified) < ($1.info?.since ?? $1.modified) }
    }

    /// Stale: no hook has touched it for 12 hours, or its transcript is gone.
    /// Catches sessions that ended without SessionEnd (app closed, crash, another machine).
    static func isStale(_ s: WaitingSession, now: Date) -> Bool {
        if now.timeIntervalSince(s.modified) > maxAge { return true }
        if let t = s.info?.transcriptPath, !FileManager.default.fileExists(atPath: t) { return true }
        return false
    }

    /// Deletes stale entries and returns their ids.
    @discardableResult
    func prune(now: Date = Date()) -> [String] {
        let stale = waitingSessions().compactMap(entry).filter { BulbStore.isStale($0, now: now) }.map(\.id)
        stale.forEach(clear)
        return stale
    }
}
