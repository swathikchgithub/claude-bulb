import Foundation

/// Disk, memory and background services that belong to Claude, as menu or terminal lines.
/// Single responsibility: summarise and format. The scanners do the reading.
struct FootprintReport {
    let paths: FootprintPaths
    let disk: [DiskItem]
    let processes: [ClaudeProcess]
    let services: [ServiceInfo]

    static func scanNow() -> FootprintReport {
        let p = FootprintPaths.current()
        return FootprintReport(paths: p, disk: DiskScanner.scan(p), processes: ProcessScanner.scan(),
                               services: ServiceScanner.scan(p))
    }

    var diskTotal: Int64 { disk.reduce(0) { $0 + $1.bytes } }
    var memoryTotalKB: Int { processes.reduce(0) { $0 + $1.info.rssKB } }

    /// Decimal units, like Finder (du -h uses 1024, so it shows smaller numbers).
    static func bytes(_ b: Int64) -> String {
        b == 0 ? "empty" : ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    /// Cache folders can have 150-character names; keep menu lines readable.
    static func short(_ s: String, max: Int = 48) -> String { s.count <= max ? s : s.prefix(max - 1) + "…" }
    static func memory(kb: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(kb) * 1024, countStyle: .memory) }

    var diskHeader: String { "Disk: \(Self.bytes(diskTotal)) in \(disk.count) locations" }

    func diskLine(_ d: DiskItem) -> String { "\(Self.bytes(d.bytes))  \(Self.short(d.label))  \(paths.display(d.url))" }
    func partLine(_ part: (name: String, bytes: Int64)) -> String { "    \(Self.bytes(part.bytes))  \(Self.short(part.name))" }

    var memoryHeader: String {
        "Memory: \(Self.memory(kb: memoryTotalKB)) in \(processes.count) processes"
    }

    /// One line per group that has processes, e.g. "1.2 GB  Claude app (9)". Time O(P).
    var memoryLines: [String] {
        ProcGroup.allCases.compactMap { g in
            let members = processes.filter { $0.group == g }
            guard !members.isEmpty else { return nil }
            return "\(Self.memory(kb: members.reduce(0) { $0 + $1.info.rssKB }))  \(g.rawValue) (\(members.count))"
        }
    }

    var biggestLine: String? {
        let top = processes.sorted { $0.info.rssKB > $1.info.rssKB }.prefix(3)
        guard !top.isEmpty else { return nil }
        return "Biggest: " + top.map { "\($0.info.name) \(Self.memory(kb: $0.info.rssKB))" }.joined(separator: ", ")
    }

    var serviceHeader: String { "Background services: \(services.count)" }

    func serviceLine(_ s: ServiceInfo) -> String {
        let state = !s.loaded ? "installed, not loaded" : (s.pid.map { "running, pid \($0)" } ?? "not running")
        return s.name == s.label ? "\(s.name): \(state)" : "\(s.name) (\(s.label)): \(state)"
    }

    /// Plain-text report for `claude-bulb footprint`.
    var text: String {
        var out = ["Claude on this Mac", "", diskHeader]
        for d in disk { out.append("  " + diskLine(d)); out += d.parts.map { "  " + partLine($0) } }
        out += ["", memoryHeader + " (shared memory is counted once per process)"] + memoryLines.map { "  " + $0 }
        if let b = biggestLine { out.append("  " + b) }
        out += ["", serviceHeader + " (launchd, your user)"] + services.map { "  " + serviceLine($0) }
        return out.joined(separator: "\n")
    }
}
