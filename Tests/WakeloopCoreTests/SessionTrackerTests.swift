import Testing
import Foundation
@testable import WakeloopCore

struct SessionTrackerTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func holdsWhileWorkingAndReleasesOnStop() {
        var t = SessionTracker()
        t.apply(.promptSubmit, session: "a", at: t0)
        #expect(t.shouldHold(at: t0))
        t.apply(.stop, session: "a", at: t0)
        #expect(!(t.shouldHold(at: t0)))
    }

    @Test func waitingHoldsOnlyForGracePeriod() {
        var t = SessionTracker(gracePeriod: 300)
        t.apply(.needsInput, session: "a", at: t0)
        #expect(t.shouldHold(at: t0.addingTimeInterval(299)))
        #expect(!(t.shouldHold(at: t0.addingTimeInterval(301))))
    }

    @Test func anyWorkingSessionKeepsHold() {
        var t = SessionTracker()
        t.apply(.promptSubmit, session: "a", at: t0)
        t.apply(.promptSubmit, session: "b", at: t0)
        t.apply(.stop, session: "a", at: t0)
        #expect(t.shouldHold(at: t0))
        t.apply(.sessionEnd, session: "b", at: t0)
        #expect(!(t.shouldHold(at: t0)))
    }

    @Test func payloadParsing() {
        let json = #"{"hook_event_name":"Notification","session_id":"s1","notification_type":"permission_prompt"}"#
        let p = HookPayload.parse(Data(json.utf8))
        #expect(p?.session == "s1")
        #expect(p?.event == .needsInput)
    }

    @Test func quotaAutoResumeNotifications() {
        func event(_ type: String) -> AgentEvent? {
            HookPayload.parse(Data(#"{"hook_event_name":"Notification","session_id":"q1","notification_type":"\#(type)"}"#.utf8))?.event
        }
        #expect(event("quota_auto_resume_fired") == .promptSubmit)
        #expect(event("quota_auto_resume_stale") == .stop)
        #expect(event("quota_auto_resume_disabled") == .stop)
        #expect(event("auth_success") == .other)
    }

    @Test func codexEventsParse() {
        func event(_ name: String) -> AgentEvent? {
            HookPayload.parse(Data(#"{"hook_event_name":"\#(name)","session_id":"c1"}"#.utf8))?.event
        }
        #expect(event("UserPromptSubmit") == .promptSubmit)
        #expect(event("PermissionRequest") == .needsInput)
        #expect(event("Interrupt") == .stop)
        #expect(event("PreToolUse") == .other)
    }
}

struct SafetyGuardTests {
    @Test func batteryFloorHasHysteresis() {
        var g = SafetyGuard(batteryFloor: 20, batteryResume: 25)
        func v(_ p: Int, ac: Bool = false) -> GuardVerdict { g.evaluate(PowerStatus(batteryPercent: p, onAC: ac, thermalHot: false)) }
        #expect(v(50) == .allowed)
        #expect(v(20) == .lowBattery)
        #expect(v(23) == .lowBattery)
        #expect(v(25) == .allowed)
        #expect(v(20) == .lowBattery)
        #expect(v(10, ac: true) == .allowed)
    }

    @Test func heatAlwaysBlocks() {
        var g = SafetyGuard()
        #expect(g.evaluate(PowerStatus(batteryPercent: nil, onAC: true, thermalHot: true)) == .tooHot)
    }
}

struct WorkingCountTests {
    @Test func countsOnlyWorkingSessions() {
        var t = SessionTracker()
        t.apply(.promptSubmit, session: "a")
        t.apply(.promptSubmit, session: "b")
        t.apply(.sessionStart, session: "c")
        t.apply(.needsInput, session: "d")
        #expect(t.workingCount == 2)
        t.apply(.stop, session: "a")
        #expect(t.workingCount == 1)
    }
}

struct WorkingNamesTests {
    @Test func namesComeFromCwdAndOnlyListWorkingSessions() {
        var t = SessionTracker()
        t.apply(.promptSubmit, session: "a", cwd: "/Users/x/Product/Wakeloop")
        t.apply(.promptSubmit, session: "b", cwd: "/Users/x/Product/Breakout")
        t.apply(.promptSubmit, session: "c")
        t.apply(.sessionStart, session: "d", cwd: "/Users/x/idle-project")
        #expect(t.workingNames == ["Breakout", "Wakeloop", "c"])
        t.apply(.stop, session: "a")
        t.apply(.sessionEnd, session: "b")
        #expect(t.workingNames == ["c"])
    }
    @Test func payloadCarriesCwd() {
        let p = HookPayload.parse(Data(#"{"hook_event_name":"UserPromptSubmit","session_id":"s","cwd":"/a/b"}"#.utf8))
        #expect(p?.cwd == "/a/b")
    }
}

struct SubagentTests {
    @Test func subagentsHoldAfterParentStopsAndAreLabelled() {
        var t = SessionTracker()
        t.apply(.promptSubmit, session: "a", cwd: "/x/Wakeloop")
        t.apply(.subagentStart(id: "1", type: "Explore"), session: "a")
        t.apply(.subagentStart(id: "2", type: "Plan"), session: "a")
        t.apply(.stop, session: "a")
        #expect(t.shouldHold())
        #expect(t.workingCount == 2)
        #expect(t.workingNames == ["Wakeloop > subagent (Explore)", "Wakeloop > subagent (Plan)"])
        t.apply(.subagentStop(id: "1"), session: "a")
        t.apply(.subagentStop(id: "2"), session: "a")
        #expect(!t.shouldHold())
        #expect(t.workingCount == 0)
    }
    @Test func staleSubagentsExpireAndSessionEndClears() {
        var t = SessionTracker()
        t.apply(.subagentStart(id: "1", type: "x"), session: "a", at: Date(timeIntervalSinceNow: -7200))
        #expect(!t.shouldHold())
        t.apply(.subagentStart(id: "2", type: "x"), session: "b")
        t.apply(.sessionEnd, session: "b")
        #expect(!t.shouldHold())
    }
    @Test func parsesSubagentHooks() {
        let s = HookPayload.parse(Data(#"{"hook_event_name":"SubagentStart","session_id":"s","agent_id":"i1","agent_type":"Explore"}"#.utf8))
        #expect(s?.event == .subagentStart(id: "i1", type: "Explore"))
        let e = HookPayload.parse(Data(#"{"hook_event_name":"SubagentStop","session_id":"s","agent_id":"i1"}"#.utf8))
        #expect(e?.event == .subagentStop(id: "i1"))
    }
}

struct WorkerGroupTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func subagentsOfOneProjectShareOneGroup() {
        var t = SessionTracker()
        t.apply(.promptSubmit, session: "a", cwd: "/x/Wakeloop", at: t0)
        for (i, type) in ["Explore", "Plan", "Bash", "general"].enumerated() {
            t.apply(.subagentStart(id: "\(i)", type: type), session: "a", at: t0)
        }
        #expect(t.groups(at: t0) == [WorkerGroup(project: "Wakeloop", mainWorking: true, subagents: ["Bash", "Explore", "Plan", "general"], subagentTotal: 4)])
    }
    @Test func sessionsInSameFolderMerge() {
        var t = SessionTracker()
        t.apply(.promptSubmit, session: "a", cwd: "/x/Wakeloop", at: t0)
        t.apply(.stop, session: "b", cwd: "/y/Wakeloop", at: t0)
        t.apply(.subagentStart(id: "1", type: "Plan"), session: "b", at: t0)
        #expect(t.groups(at: t0) == [WorkerGroup(project: "Wakeloop", mainWorking: true, subagents: ["Plan"], subagentTotal: 1)])
    }
    @Test func groupsSortedByProjectAndIdleSessionsExcluded() {
        var t = SessionTracker()
        t.apply(.promptSubmit, session: "a", cwd: "/x/Zeta", at: t0)
        t.apply(.sessionStart, session: "b", cwd: "/x/Alpha", at: t0)
        t.apply(.subagentStart(id: "1", type: "Explore"), session: "c", cwd: "/x/Mid", at: t0)
        #expect(t.groups(at: t0).map(\.project) == ["Mid", "Zeta"])
        #expect(t.groups(at: t0).map(\.mainWorking) == [false, true])
    }
    @Test func duplicateSubagentTypesCollapse() {
        var t = SessionTracker()
        for (i, type) in ["Explore", "Explore", "Plan", "Explore"].enumerated() {
            t.apply(.subagentStart(id: "\(i)", type: type), session: "a", at: t0)
        }
        #expect(t.groups(at: t0).first?.subagents == ["Explore ×3", "Plan"])
        #expect(t.groups(at: t0).first?.subagentTotal == 4)
    }
    @Test func longNamesAreTruncated() {
        let long = String(repeating: "a", count: 200)
        let s = truncated(long)
        #expect(s.count == 40)
        #expect(s.hasSuffix("…"))
        #expect(truncated("short") == "short")
        var t = SessionTracker()
        t.apply(.promptSubmit, session: "a", cwd: "/x/" + long, at: t0)
        #expect(t.groups(at: t0).first?.project.count == 40)
    }
    @Test func subagentRowsAreCapped() {
        var t = SessionTracker()
        for i in 0..<100 {
            t.apply(.subagentStart(id: "\(i)", type: String(format: "t%02d", i)), session: "a", at: t0)
        }
        let rows = t.groups(maxSubagentRows: 10, at: t0)[0].subagents
        #expect(rows.count == 11)
        #expect(rows.last == "… and 90 more")
        #expect(t.groups(at: t0)[0].subagents.count == 11)
        #expect(t.groups(at: t0)[0].subagentTotal == 100)
    }
    @Test func expiredSubagentsExcluded() {
        var t = SessionTracker()
        t.apply(.subagentStart(id: "1", type: "Explore"), session: "a", at: t0.addingTimeInterval(-7200))
        t.apply(.subagentStart(id: "2", type: "Plan"), session: "a", at: t0)
        #expect(t.groups(at: t0) == [WorkerGroup(project: "a", mainWorking: false, subagents: ["Plan"], subagentTotal: 1)])
        t.apply(.subagentStop(id: "2"), session: "a", at: t0)
        #expect(t.groups(at: t0).isEmpty)
    }
}

struct LidGuardTests {
    private func battery(_ pct: Int) -> PowerStatus { PowerStatus(batteryPercent: pct, onAC: false, thermalHot: false) }
    private let charger = PowerStatus(batteryPercent: 50, onAC: true, thermalHot: false)

    @Test func chargerAlwaysAllowsAndBatteryIsRefusedByDefault() {
        var g = LidGuard()
        let r1 = g.allows(charger, batteryAllowed: false)
        #expect(r1)
        let r2 = g.allows(battery(90), batteryAllowed: false)
        #expect(!r2)
    }

    @Test func optInBatteryStopsAtThirtyAndResumesAtThirtyFive() {
        var g = LidGuard()
        let r3 = g.allows(battery(50), batteryAllowed: true)
        #expect(r3)
        let r4 = g.allows(battery(30), batteryAllowed: true)
        #expect(!r4)
        let r5 = g.allows(battery(33), batteryAllowed: true)
        #expect(!r5)
        let r6 = g.allows(battery(35), batteryAllowed: true)
        #expect(r6)
        let r7 = g.allows(battery(30), batteryAllowed: true)
        #expect(!r7)
        let r8 = g.allows(charger, batteryAllowed: true)
        #expect(r8)
    }

    @Test func desktopWithoutBatteryIsAllowed() {
        var g = LidGuard()
        let r9 = g.allows(PowerStatus(batteryPercent: nil, onAC: true, thermalHot: false), batteryAllowed: false)
        #expect(r9)
    }
}

struct StaleSubagentTests {
    private let transcript = "/p/proj/sess-1.jsonl"

    @Test func killedSubagentIsDroppedOnceItsTranscriptGoesQuiet() {
        var t = SessionTracker()
        let now = Date()
        t.apply(.promptSubmit, session: "sess-1", cwd: "/x/Wakeloop", transcript: transcript)
        t.apply(.subagentStart(id: "dead", type: "general-purpose"), session: "sess-1")
        t.apply(.subagentStart(id: "live", type: "Explore"), session: "sess-1")
        var asked: [String] = []
        t.pruneStaleSubagents(staleAfter: 180, at: now) { path in
            asked.append(path)
            return path.hasSuffix("agent-dead.jsonl") ? now.addingTimeInterval(-600) : now.addingTimeInterval(-5)
        }
        #expect(asked.contains("/p/proj/sess-1/subagents/agent-dead.jsonl"))
        #expect(t.subagents["sess-1"]?.keys.sorted() == ["live"])
    }

    @Test func missingTranscriptOrUnknownPathKeepsTheSubagent() {
        var t = SessionTracker()
        t.apply(.subagentStart(id: "a", type: "x"), session: "no-path")
        t.apply(.subagentStart(id: "b", type: "x"), session: "s2", transcript: transcript)
        t.pruneStaleSubagents { _ in nil }
        #expect(t.subagents["no-path"]?.count == 1)
        #expect(t.subagents["s2"]?.count == 1)
    }
}

struct HoldCapTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ hours: Double) -> Date { t0.addingTimeInterval(hours * 3600) }

    @Test func tripsAfterLimitAndStaysTrippedUntilActivity() {
        var cap = HoldCap(limit: 8 * 3600, since: t0)
        let before = cap.tripped(holding: true, at: at(7.99))
        let atLimit = cap.tripped(holding: true, at: at(8))
        // Still held after the trip, with no activity: the cap does not re-engage on its own.
        let later = cap.tripped(holding: true, at: at(9))
        cap.activity(at: at(9))
        let afterActivity = cap.tripped(holding: true, at: at(9.01))
        // The timer restarted at the activity, so it trips 8 hours later.
        let nextTrip = cap.tripped(holding: true, at: at(17.01))
        #expect(!before)
        #expect(atLimit)
        #expect(later)
        #expect(!afterActivity)
        #expect(nextTrip)
    }

    @Test func activityRestartsTheQuietTimer() {
        var cap = HoldCap(limit: 8 * 3600, since: t0)
        cap.activity(at: at(7))
        let early = cap.tripped(holding: true, at: at(14))
        let late = cap.tripped(holding: true, at: at(15))
        #expect(!early)
        #expect(late)
    }

    @Test func quietTimerOnlyRunsWhileHolding() {
        var cap = HoldCap(limit: 8 * 3600, since: t0)
        let idle = cap.tripped(holding: false, at: at(20))
        let justBefore = cap.tripped(holding: true, at: at(27.9))
        let atLimit = cap.tripped(holding: true, at: at(28))
        #expect(!idle)
        #expect(!justBefore)
        #expect(atLimit)
    }

    @Test func offNeverTrips() {
        var cap = HoldCap(limit: nil, since: t0)
        let tripped = cap.tripped(holding: true, at: at(100))
        #expect(!tripped)
    }

    @Test func turningOffClearsATrippedCap() {
        var cap = HoldCap(limit: 8 * 3600, since: t0)
        let trip = cap.tripped(holding: true, at: at(8))
        cap.limit = nil
        let off = cap.tripped(holding: true, at: at(9))
        // Nine quiet hours are under a 12-hour limit, so the old trip must not carry over.
        cap.limit = 12 * 3600
        let fresh = cap.tripped(holding: true, at: at(9))
        #expect(trip)
        #expect(!off)
        #expect(!fresh)
    }
}

struct CrashedSessionTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func crashedWorkingSessionExpiresAfterTwoHours() {
        var t = SessionTracker()
        t.apply(.promptSubmit, session: "a", cwd: "/x/Wakeloop", at: t0)
        t.pruneCrashedSessions(at: t0.addingTimeInterval(7199)) { _ in nil }
        #expect(t.shouldHold(at: t0.addingTimeInterval(7199)))
        t.pruneCrashedSessions(at: t0.addingTimeInterval(7201)) { _ in nil }
        #expect(!t.shouldHold(at: t0.addingTimeInterval(7201)))
        #expect(t.workingCount == 0)
        #expect(t.sessions["a"] == nil)
    }

    @Test func hookEventKeepsSessionAlive() {
        var t = SessionTracker()
        t.apply(.promptSubmit, session: "a", at: t0)
        t.apply(.other, session: "a", at: t0.addingTimeInterval(3600))
        t.pruneCrashedSessions(at: t0.addingTimeInterval(7201)) { _ in nil }
        #expect(t.sessions["a"] == .working)
        t.pruneCrashedSessions(at: t0.addingTimeInterval(3600 + 7201)) { _ in nil }
        #expect(t.sessions["a"] == nil)
    }

    @Test func transcriptWriteKeepsSessionAlive() {
        var t = SessionTracker()
        let transcript = "/p/proj/sess-1.jsonl"
        t.apply(.promptSubmit, session: "a", transcript: transcript, at: t0)
        let now = t0.addingTimeInterval(3 * 3600)
        t.pruneCrashedSessions(at: now) { path in
            path == transcript ? now.addingTimeInterval(-60) : nil
        }
        #expect(t.sessions["a"] == .working)
        t.pruneCrashedSessions(at: now) { _ in nil }
        #expect(t.sessions["a"] == nil)
    }

    @Test func waitingAndIdleSessionsAreNotExpired() {
        var t = SessionTracker(gracePeriod: 300)
        t.apply(.sessionStart, session: "idle", at: t0)
        t.apply(.needsInput, session: "wait", at: t0)
        t.pruneCrashedSessions(at: t0.addingTimeInterval(3 * 3600)) { _ in nil }
        #expect(t.sessions["idle"] == .idle)
        #expect(t.sessions["wait"] == .waiting(since: t0))
    }

    @Test func processTreeHoldStillWorksAfterExpiry() {
        var t = SessionTracker()
        t.apply(.promptSubmit, session: "a", cwd: "/x/Wakeloop", at: t0)
        let now = t0.addingTimeInterval(3 * 3600)
        t.pruneCrashedSessions(at: now) { _ in nil }
        #expect(!t.shouldHold(at: now))
        // A silent 2-hour command: the agent is idle in the hooks, but its child is busy.
        let busy = ProcessTree.busyAgentDescendants([
            ProcInfo(pid: 10, ppid: 1, cpu: 0, name: "claude"),
            ProcInfo(pid: 11, ppid: 10, cpu: 95, name: "make"),
        ])
        #expect(!busy.isEmpty)
        #expect(t.wantsHold(busyChildren: busy, activeTranscripts: [], at: now))
        #expect(!t.wantsHold(busyChildren: [], activeTranscripts: [], at: now))
        let transcript = [FileStamp(path: "/p/x.jsonl", modified: now)]
        #expect(t.wantsHold(busyChildren: [], activeTranscripts: transcript, at: now))
    }
}
