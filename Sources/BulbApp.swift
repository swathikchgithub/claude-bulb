import AppKit

/// The menu bar bulb. Reads BulbStore, draws the icon, blinks, plays the sound,
/// and shows today's token use when the menu opens.
final class BulbApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store: BulbStore
    private let soundEvery: TimeInterval = 30
    private var item: NSStatusItem!
    private var muted = false
    private var waiting = false
    private var blinkOn = false
    private var lastSound = Date.distantPast
    private let muteItem = NSMenuItem(title: "Mute sound", action: #selector(toggleMute), keyEquivalent: "")
    private let menu = NSMenu()
    private var usageItems: [NSMenuItem] = []
    private var loadingUsage = false

    init(store: BulbStore) { self.store = store }

    func applicationDidFinishLaunching(_ note: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        buildMenu()
        item.menu = menu
        draw()
        // Poll every 0.5 s: check the state folder and flip the blink.
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func buildMenu() {
        menu.delegate = self
        usageItems = [NSMenuItem(title: "Today · loading usage…", action: nil, keyEquivalent: "")]
        menu.addItem(usageItems[0])
        menu.addItem(.separator())
        muteItem.target = self
        menu.addItem(muteItem)
        let clear = NSMenuItem(title: "Clear now", action: #selector(clearNow), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Claude Bulb", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func menuWillOpen(_ menu: NSMenu) { refreshUsage() }

    /// Reading transcripts takes about half a second, so it runs off the main thread.
    /// The menu shows the previous numbers until the new ones arrive.
    private func refreshUsage() {
        guard !loadingUsage else { return }
        loadingUsage = true
        DispatchQueue.global(qos: .userInitiated).async {
            let report = UsageReport.build(root: UsageReader.defaultRoot(), since: UsageReport.startOfToday(),
                                           prices: PriceTable.load(from: PriceTable.defaultURL()))
            DispatchQueue.main.async {
                self.showUsage(report)
                self.loadingUsage = false
            }
        }
    }

    /// Greyed-out lines at the top of the menu: a header, the day's total, then the 5 costliest sessions.
    private func showUsage(_ r: UsageReport) {
        usageItems.forEach { menu.removeItem($0) }
        let lines = ["Today · API-equivalent cost", "All sessions: " + r.total.line]
            + r.sessions.prefix(5).map { "\($0.label): \($0.line)" }
        usageItems = lines.map { NSMenuItem(title: $0, action: nil, keyEquivalent: "") }
        for (i, line) in usageItems.enumerated() { menu.insertItem(line, at: i) }
    }

    private func tick() {
        let nowWaiting = !store.waitingSessions().isEmpty
        if nowWaiting && !waiting { lastSound = .distantPast }   // just turned red: sound right away
        waiting = nowWaiting
        blinkOn = waiting ? !blinkOn : false
        if waiting && Date().timeIntervalSince(lastSound) >= soundEvery { playSound() }
        draw()
    }

    private func playSound() {
        lastSound = Date()
        if !muted { NSSound(named: "Glass")?.play() }
    }

    private func draw() {
        let name = blinkOn ? "lightbulb.fill" : "lightbulb"
        let color: NSColor = waiting ? .systemRed : .labelColor
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            .applying(.init(paletteColors: [color]))
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Claude bulb")?
            .withSymbolConfiguration(config)
        image?.isTemplate = !waiting   // calm state follows the menu bar's light/dark colour
        item.button?.image = image
        item.button?.toolTip = waiting ? "Claude is waiting for you" : "Claude is working or idle"
    }

    @objc private func toggleMute() {
        muted.toggle()
        muteItem.state = muted ? .on : .off
    }

    @objc private func clearNow() {
        store.clearAll()
        tick()
    }
}
