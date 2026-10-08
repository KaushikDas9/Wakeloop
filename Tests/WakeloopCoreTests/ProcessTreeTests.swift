import Testing
import Foundation
@testable import WakeloopCore

struct ProcessTreeTests {
    @Test func parsesPsOutputIncludingSpacesInPaths() {
        let out = """
          1     0   0.0 /sbin/launchd
        100     1   0.1 /Users/me/Library/Application Support/claude/claude
        """
        let p = ProcessTree.parse(out)
        #expect(p.count == 2)
        #expect(p[1] == ProcInfo(pid: 100, ppid: 1, cpu: 0.1, name: "claude"))
    }

    @Test func busyGrandchildOfAgentCounts() {
        let procs = [
            ProcInfo(pid: 10, ppid: 1, cpu: 0, name: "claude"),
            ProcInfo(pid: 11, ppid: 10, cpu: 0, name: "zsh"),
            ProcInfo(pid: 12, ppid: 11, cpu: 85, name: "swift-build"),
        ]
        #expect(ProcessTree.busyAgentDescendants(procs).map(\.pid) == [12])
    }

    @Test func idleChildrenAndUnrelatedBusyProcessesIgnored() {
        let procs = [
            ProcInfo(pid: 10, ppid: 1, cpu: 0, name: "codex"),
            ProcInfo(pid: 11, ppid: 10, cpu: 0.2, name: "node"),     // idle MCP server
            ProcInfo(pid: 20, ppid: 1, cpu: 99, name: "Xcode"),      // busy, but not an agent's
        ]
        #expect(ProcessTree.busyAgentDescendants(procs).isEmpty)
    }

    @Test func pidCycleDoesNotHang() {
        let procs = [
            ProcInfo(pid: 10, ppid: 1, cpu: 0, name: "claude"),
            ProcInfo(pid: 11, ppid: 10, cpu: 50, name: "a"),
            ProcInfo(pid: 12, ppid: 11, cpu: 50, name: "b"),
            ProcInfo(pid: 11, ppid: 12, cpu: 50, name: "a"),
        ]
        #expect(!ProcessTree.busyAgentDescendants(procs).isEmpty)
    }
}
