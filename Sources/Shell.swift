import Foundation

/// Runs a fixed system program and returns its output.
/// No shell is involved, so nothing can be injected into the command.
enum Shell {
    static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()   // read before wait: no pipe deadlock
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Test seam: if the env var names a file, its contents stand in for the command's output.
    static func output(_ path: String, _ args: [String], fixtureEnv: String) -> String {
        if let file = ProcessInfo.processInfo.environment[fixtureEnv] {
            return (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
        }
        return run(path, args)
    }
}
