import Foundation

/// Parses Claude Code hook JSON (HTTP hook body). Re-verify against current hooks docs: formats change.
public enum HookPayload {
    public static func parse(_ data: Data) -> (session: String, event: AgentEvent, cwd: String?)? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = obj["hook_event_name"] as? String else { return nil }
        let session = (obj["session_id"] as? String) ?? "unknown"
        let cwd = obj["cwd"] as? String
        return (session, classify(name, obj), cwd)
    }

    private static func classify(_ name: String, _ obj: [String: Any]) -> AgentEvent {
        switch name {
        case "SessionStart": return .sessionStart
        case "UserPromptSubmit": return .promptSubmit
        case "Stop", "StopFailure", "Interrupt": return .stop
        case "SessionEnd": return .sessionEnd
        case "PermissionRequest": return .needsInput
        case "SubagentStart":
            return .subagentStart(id: obj["agent_id"] as? String ?? "unknown", type: obj["agent_type"] as? String ?? "agent")
        case "SubagentStop": return .subagentStop(id: obj["agent_id"] as? String ?? "unknown")
        case "Notification":
            let type = obj["notification_type"] as? String ?? ""
            // Claude Code v2.1.234+: auto-continue after a usage limit. These fire when the wait ends, not when it starts.
            switch type {
            case "quota_auto_resume_fired": return .promptSubmit   // task continues on its own: working
            case "quota_auto_resume_stale", "quota_auto_resume_disabled": return .stop
            default: break
            }
            let waiting: Set<String> = ["permission_prompt", "idle_prompt", "agent_needs_input"]
            return waiting.contains(type) ? .needsInput : .other
        default: return .other
        }
    }
}
