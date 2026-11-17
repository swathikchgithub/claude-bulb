import Foundation

/// Owns the on-disk state: one empty file per Claude session that is waiting on you.
/// Single responsibility: create, delete and count those files. No UI, no sound.
struct BulbStore {
    let dir: URL

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

    func markWaiting(_ sessionId: String) throws {
        guard BulbStore.isSafeId(sessionId) else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir.appendingPathComponent(sessionId).path, contents: nil)
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
}
