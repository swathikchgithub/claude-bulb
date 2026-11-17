import AppKit

// One binary, three modes:
//   claude-bulb            -> run the menu bar app
//   claude-bulb on|off     -> called by Claude Code hooks (reads hook JSON on stdin)
//   claude-bulb usage      -> print today's tokens and API-equivalent cost
let store = BulbStore.defaultStore()
let args = CommandLine.arguments

// claude-bulb usage [--since YYYY-MM-DD]  -> print token use and API-equivalent cost
if args.count > 1 && args[1] == "usage" {
    var since = UsageReport.startOfToday()
    if args.count > 3 && args[2] == "--since" {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: args[3]) else {
            FileHandle.standardError.write("bad date, use YYYY-MM-DD\n".data(using: .utf8)!)
            exit(2)
        }
        since = d
    }
    let report = UsageReport.build(root: UsageReader.defaultRoot(), since: since,
                                   prices: PriceTable.load(from: PriceTable.defaultURL()))
    print(report.text)
    exit(0)
}

if args.count > 1 {
    let input = args[1] == "clear-all" ? Data() : FileHandle.standardInput.readDataToEndOfFile()
    exit(HookCommand.run(args[1], store: store, stdin: input))
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu bar only: no Dock icon, no window
let delegate = BulbApp(store: store)
app.delegate = delegate
app.run()
