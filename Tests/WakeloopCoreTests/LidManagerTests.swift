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
