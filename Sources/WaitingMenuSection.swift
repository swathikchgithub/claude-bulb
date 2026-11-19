import AppKit

/// The "Waiting on you" lines at the top of the bulb's menu.
/// Rebuilt each time the menu opens; clicking a session's line clears only that session.
final class WaitingMenuSection: NSObject {
    let end = NSMenuItem.separator()   // everything above this belongs to the section
    private let store: BulbStore
    private let onChange: () -> Void
    private var items: [NSMenuItem] = []

    init(store: BulbStore, onChange: @escaping () -> Void) {
        self.store = store
        self.onChange = onChange
    }

    func refresh(in menu: NSMenu, now: Date = Date()) {
        items.forEach { menu.removeItem($0) }
        let sessions = store.entries()
        items = [plain(sessions.isEmpty ? "Nothing is waiting on you" : "Waiting on you (\(sessions.count)) · click one to clear it")]
        for w in sessions { items += lines(for: w, now: now) }
        for (i, line) in items.enumerated() { menu.insertItem(line, at: i) }
    }

    private func lines(for w: WaitingSession, now: Date) -> [NSMenuItem] {
        let title = NSMenuItem(title: WaitingList.title(w, now: now), action: #selector(clearOne(_:)), keyEquivalent: "")
        title.target = self
        title.representedObject = w.id
        title.toolTip = (["Click to clear this session", "Session \(w.id)"] + [w.info?.transcriptPath].compactMap { $0 })
            .joined(separator: "\n")
        return [title] + [WaitingList.detail(w)].compactMap { $0 }.map { plain("      \"\($0)\"") }
    }

    private func plain(_ text: String) -> NSMenuItem { NSMenuItem(title: text, action: nil, keyEquivalent: "") }

    @objc private func clearOne(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        store.clear(id)
        onChange()
    }
}
