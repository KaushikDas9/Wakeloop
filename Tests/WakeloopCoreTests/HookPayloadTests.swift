import Testing
import Foundation
@testable import WakeloopCore

struct HookPayloadTests {
    private func parse(_ json: String) -> (session: String, event: AgentEvent, cwd: String?, transcript: String?)? {
        HookPayload.parse(Data(json.utf8))
    }

    @Test func codexCommonFieldsParse() throws {
        let p = try #require(parse(#"{"session_id":"abc","cwd":"/Users/me/app","transcript_path":"/Users/me/.codex/sessions/2026/10/15/rollout.jsonl","hook_event_name":"UserPromptSubmit","model":"gpt-5","turn_id":"t1","prompt":"hi","permission_mode":"default"}"#))
        #expect(p.session == "abc")
        #expect(p.event == .promptSubmit)
        #expect(p.cwd == "/Users/me/app")
        #expect(p.transcript == "/Users/me/.codex/sessions/2026/10/15/rollout.jsonl")
    }

    @Test func codexStopInterruptAndPermissionRequestClassify() {
        #expect(parse(#"{"session_id":"s","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"done"}"#)?.event == .stop)
        #expect(parse(#"{"session_id":"s","hook_event_name":"Interrupt","turn_id":"t"}"#)?.event == .stop)
        #expect(parse(#"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{}}"#)?.event == .needsInput)
        #expect(parse(#"{"session_id":"s","hook_event_name":"SessionEnd","reason":"other"}"#)?.event == .sessionEnd)
        #expect(parse(#"{"session_id":"s","hook_event_name":"SessionStart","source":"startup"}"#)?.event == .sessionStart)
    }

    @Test func missingSessionIdIsUnknownAndUnknownEventIsOther() {
        #expect(parse(#"{"hook_event_name":"PreToolUse"}"#)?.session == "unknown")
        #expect(parse(#"{"hook_event_name":"PreToolUse"}"#)?.event == .other)
        #expect(parse("not json") == nil)
    }

    @Test func agentFromTranscriptPath() {
        #expect(HookPayload.agent(transcript: "/Users/me/.codex/sessions/2026/10/15/rollout.jsonl") == "codex")
        #expect(HookPayload.agent(transcript: "/Users/me/.claude/projects/app/s.jsonl") == "claude")
        #expect(HookPayload.agent(transcript: "/tmp/other.jsonl") == nil)
        #expect(HookPayload.agent(transcript: "") == nil)
        #expect(HookPayload.agent(transcript: nil) == nil)
    }

    @Test func codexSnippetMatchesCodexEventsAndTimeouts() throws {
        let text = try #require(HookSnippet.json(for: "codex"))
        let root = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let hooks = try #require(root["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == Set(HookSnippet.codexEvents))
        #expect(hooks["Interrupt"] != nil)
        #expect(hooks["Notification"] == nil)
        for (_, value) in hooks {
            let entry = ((value as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first
            #expect(entry?["timeout"] as? Int == 3)
        }
    }

    @Test func claudeSnippetKeepsItsEventsAndFiveSecondTimeout() throws {
        let text = try #require(HookSnippet.json(for: "claude"))
        let root = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let hooks = try #require(root["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == Set(HookSnippet.claudeEvents))
        #expect(hooks["Interrupt"] == nil)
        let entry = ((hooks["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first
        #expect(entry?["timeout"] as? Int == 5)
    }

    @Test func unknownAgentHasNoSnippet() {
        #expect(HookSnippet.json(for: "cursor") == nil)
    }
}
