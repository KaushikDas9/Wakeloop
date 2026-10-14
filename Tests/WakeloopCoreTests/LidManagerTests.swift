import Testing
import Foundation
@testable import WakeloopCore

struct LidManagerTests {
    @Test func usesNonInteractiveSudoWithExactPmsetArgs() {
        var calls: [[String]] = []
        let m = LidManager { path, args in calls.append([path] + args); return (0, "") }
        #expect(m.setSleepDisabled(false))
        #expect(calls == [["/usr/bin/sudo", "-n", "/usr/bin/pmset", "disablesleep", "0"]])
    }

    @Test func failedSudoLeavesStateInactive() {
        let m = LidManager { _, _ in (1, "") }
        #expect(!m.setSleepDisabled(true))
        #expect(!m.isActive)
    }

    @Test func parsesSleepDisabled() {
        #expect(LidManager.parseSleepDisabled("System-wide power settings:\n SleepDisabled\t\t1\n") == true)
        #expect(LidManager.parseSleepDisabled(" SleepDisabled\t\t0\n sleep 1") == false)
        #expect(LidManager.parseSleepDisabled(" sleep 1") == nil)
    }

    @Test func sudoersRuleCoversOnlyTheTwoCommands() {
        let line = LidManager.sudoersLine(user: "me")
        #expect(line == "me ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1")
    }

    @Test func watchdogRestoresSleepAfterParentExits() {
        let s = LidManager.watchdogScript(parentPID: 123)
        #expect(s.contains("kill -0 123"))
        #expect(s.hasSuffix("/usr/bin/pmset disablesleep 0"))
    }
}

struct LidSetupTests {
    @Test func installScriptValidatesBeforeInstalling() {
        let s = LidManager.installScript(user: "koushik.das")!
        #expect(s.contains("koushik.das ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1"))
        let check = s.range(of: "visudo -cf")!.lowerBound
        let install = s.range(of: "/usr/bin/install")!.lowerBound
        #expect(check < install)
        #expect(s.hasPrefix("set -e"))
        #expect(s.contains("-m 0440 -o root -g wheel"))
    }

    @Test func installScriptRejectsUnsafeAccountNames() {
        for bad in ["", "a b", "a'b", "a;rm", "a\nb", "é", "a$b"] { #expect(LidManager.installScript(user: bad) == nil) }
    }

    @Test func appleScriptEscapesQuotesBackslashesAndNewlines() {
        let a = LidManager.appleScript(running: "echo \"hi\"\\n\nx", prompt: "p")
        #expect(a == "do shell script \"echo \\\"hi\\\"\\\\n\\nx\" with prompt \"p\" with administrator privileges")
    }

    @Test func isSetUpUsesNonInteractiveSudoList() {
        var calls: [[String]] = []
        let m = LidManager { path, args in calls.append([path] + args); return (0, "") }
        #expect(m.isSetUp())
        #expect(calls == [["/usr/bin/sudo", "-n", "-l", "/usr/bin/pmset", "disablesleep", "1"]])
        #expect(!LidManager { _, _ in (1, "") }.isSetUp())
    }
}
