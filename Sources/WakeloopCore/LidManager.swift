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

    public static let sudoersPath = "/etc/sudoers.d/wakeloop"

    /// True when the sudoers rule is installed and works without a password.
    public func isSetUp() -> Bool {
        run("/usr/bin/sudo", ["-n", "-l", Self.pmset, "disablesleep", "1"]).status == 0
    }

    /// Script run as root by the in-app setup button: validates the rule with visudo before installing it, so a bad
    /// rule can never reach /etc/sudoers.d. nil when the account name is not a plain name (it goes into the rule).
    public static func installScript(user: String) -> String? {
        guard !user.isEmpty, user.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }) else { return nil }
        return """
        set -e
        T=$(/usr/bin/mktemp /tmp/wakeloop-sudoers.XXXXXX)
        trap '/bin/rm -f "$T"' EXIT
        /usr/bin/printf '%s\\n' '\(sudoersLine(user: user))' > "$T"
        /usr/sbin/visudo -cf "$T"
        /usr/bin/install -m 0440 -o root -g wheel "$T" \(sudoersPath)
        """
    }

    public static let removeScript = "/bin/rm -f \(sudoersPath)"

    /// AppleScript source that runs `shell` as root behind the standard macOS password dialog.
    public static func appleScript(running shell: String, prompt: String) -> String {
        func quoted(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n") + "\""
        }
        return "do shell script \(quoted(shell)) with prompt \(quoted(prompt)) with administrator privileges"
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
