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
