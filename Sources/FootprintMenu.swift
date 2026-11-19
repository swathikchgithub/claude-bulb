import AppKit

/// The "Claude on this Mac" submenu. Owns its refresh schedule:
/// memory and services on every open (fast), disk at most every 10 minutes (a few seconds of reading).
final class FootprintMenu: NSObject {
    let item = NSMenuItem(title: "Claude on this Mac", action: nil, keyEquivalent: "")
    private let submenu = NSMenu()
    private let diskEvery: TimeInterval = 600
    private var disk: [DiskItem] = []
    private var lastDiskScan = Date.distantPast
    private var busy = false

    override init() {
        super.init()
        item.submenu = submenu
        submenu.addItem(NSMenuItem(title: "Loading…", action: nil, keyEquivalent: ""))
    }

    /// Runs off the main thread; the submenu keeps the previous numbers until new ones arrive.
    func refresh() {
        guard !busy else { return }
        busy = true
        let needDisk = Date().timeIntervalSince(lastDiskScan) >= diskEvery
        let paths = FootprintPaths.current(), oldDisk = disk
        DispatchQueue.global(qos: .utility).async {
            let report = FootprintReport(paths: paths, disk: needDisk ? DiskScanner.scan(paths) : oldDisk,
                                         processes: ProcessScanner.scan(), services: ServiceScanner.scan(paths))
            DispatchQueue.main.async {
                if needDisk { self.disk = report.disk; self.lastDiskScan = Date() }
                self.show(report)
                self.busy = false
            }
        }
    }

    private func show(_ r: FootprintReport) {
        submenu.removeAllItems()
        add(r.diskHeader)
        for d in r.disk {
            add(r.diskLine(d), reveal: d.url)
            d.parts.forEach { add(r.partLine($0)) }
        }
        submenu.addItem(.separator())
        add(r.memoryHeader)
        r.memoryLines.forEach { add("    " + $0) }
        if let b = r.biggestLine { add("    " + b) }
        submenu.addItem(.separator())
        add(r.serviceHeader)
        r.services.forEach { add("    " + r.serviceLine($0)) }
    }

    /// Lines with a location can be clicked to show it in Finder; all others are grey text.
    private func add(_ title: String, reveal url: URL? = nil) {
        let line = NSMenuItem(title: title, action: url == nil ? nil : #selector(reveal(_:)), keyEquivalent: "")
        line.target = self
        line.representedObject = url
        if url != nil { line.toolTip = "Show in Finder" }
        submenu.addItem(line)
    }

    @objc private func reveal(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
