import AppKit

// One binary, two modes:
//   claude-bulb            -> run the menu bar app
//   claude-bulb on|off     -> called by Claude Code hooks (reads hook JSON on stdin)
let store = BulbStore.defaultStore()
let args = CommandLine.arguments

if args.count > 1 {
    let input = args[1] == "clear-all" ? Data() : FileHandle.standardInput.readDataToEndOfFile()
    exit(HookCommand.run(args[1], store: store, stdin: input))
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu bar only: no Dock icon, no window
let delegate = BulbApp(store: store)
app.delegate = delegate
app.run()
