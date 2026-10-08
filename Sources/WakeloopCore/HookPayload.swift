import Foundation

/// Parses Claude Code hook JSON (HTTP hook body). Re-verify against current hooks docs: formats change.
public enum HookPayload {
    public static func parse(_ data: Data) -> (session: String, event: AgentEvent)? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = obj["hook_event_name"] as? String else { return nil }
        let session = (obj["session_id"] as? String) ?? "unknown"
        switch name {
        case "SessionStart": return (session, .sessionStart)
        case "UserPromptSubmit": return (session, .promptSubmit)
        case "Stop", "StopFailure", "Interrupt": return (session, .stop)
        case "SessionEnd": return (session, .sessionEnd)
        case "PermissionRequest": return (session, .needsInput)
        case "Notification":
            let type = obj["notification_type"] as? String ?? ""
            // Claude Code v2.1.234+: auto-continue after a usage limit. These fire when the wait ends, not when it starts.
            switch type {
            case "quota_auto_resume_fired": return (session, .promptSubmit)   // task continues on its own: working
            case "quota_auto_resume_stale", "quota_auto_resume_disabled": return (session, .stop)
            default: break
            }
            let waiting: Set<String> = ["permission_prompt", "idle_prompt", "agent_needs_input"]
            return (session, waiting.contains(type) ? .needsInput : .other)
        default: return (session, .other)
        }
    }
}
