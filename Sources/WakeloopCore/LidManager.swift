import Foundation

/// Keeps a lid-closed Mac awake via `pmset disablesleep`, which needs root. Free-phase route: a scoped sudoers rule
/// for exactly those two commands (see `sudoersLine`). Never installs anything itself.
public final class LidManager {
    public typealias Runner = (_ path: String, _ args: [String]) -> (status: Int32, output: String)

    private let run: Runner
    private var watchdog: Process?
    public private(set) var isActive = false

    public init(runner: @escaping Runner = LidManager.systemRunner) { self.run = runner }

    public static let pmset = "/usr/bin/pmset"

    /// Returns false when sudo refuses (rule not installed) or pmset fails.
    @discardableResult
    public func setSleepDisabled(_ on: Bool) -> Bool {
        let ok = run("/usr/bin/sudo", ["-n", Self.pmset, "disablesleep", on ? "1" : "0"]).status == 0
        if ok { isActive = on }
        if ok && on { startWatchdog(parentPID: getpid()) } else if !on { stopWatchdog() }
        return ok
    }

    /// Current system value, whoever set it. nil when `pmset -g` cannot be read.
    public func sleepDisabledNow() -> Bool? {
        let r = run(Self.pmset, ["-g"])
        return r.status == 0 ? Self.parseSleepDisabled(r.output) : nil
    }

    public static func parseSleepDisabled(_ output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if f.count >= 2, f[0] == "SleepDisabled" { return f[1] == "1" }
        }
        return nil
    }

    /// Detached shell that restores normal sleep if the app dies without cleaning up (crash, kill -9).
    public static func watchdogScript(parentPID: Int32) -> String {
        "while kill -0 \(parentPID) 2>/dev/null; do sleep 5; done; /usr/bin/sudo -n \(pmset) disablesleep 0"
    }

    private func startWatchdog(parentPID: Int32) {
        stopWatchdog()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", Self.watchdogScript(parentPID: parentPID)]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); watchdog = p } catch { NSLog("Wakeloop: watchdog failed to start: \(error)") }
    }

    private func stopWatchdog() {
        watchdog?.terminate()
        watchdog = nil
    }

    /// The exact rule to add with `sudo visudo -f /etc/sudoers.d/wakeloop`.
    public static func sudoersLine(user: String) -> String {
        "\(user) ALL=(root) NOPASSWD: \(pmset) disablesleep 0, \(pmset) disablesleep 1"
    }

    public static let systemRunner: Runner = { path, args in
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice
        do { try task.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
