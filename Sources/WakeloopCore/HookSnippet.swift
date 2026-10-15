import Foundation

/// Wakeloop's hook entries for agents. The one source for `wakeloop hook-snippet` and the in-app installer.
public enum HookSnippet {
    /// Each hook POSTs its JSON to the app and ignores failures, so the agent is never blocked.
    public static let command = "curl -s -m 2 -X POST --data-binary @- http://127.0.0.1:\(wakeloopPort)/event >/dev/null || true"

    /// Codex has no Notification event but has Interrupt; Claude Code is the reverse.
    public static let claudeEvents = ["SessionStart", "UserPromptSubmit", "PermissionRequest", "Stop", "SessionEnd",
                                      "Notification", "SubagentStart", "SubagentStop"]
    public static let codexEvents = ["SessionStart", "UserPromptSubmit", "PermissionRequest", "Stop", "SessionEnd", "Interrupt"]

    public static func events(for agent: String) -> [String]? {
        switch agent {
        case "claude": return claudeEvents
        case "codex": return codexEvents
        default: return nil
        }
    }

    /// One hook group, as Claude Code's settings file expects it.
    public static func group() -> [String: Any] {
        ["hooks": [["type": "command", "command": command, "timeout": 5]]]
    }

    /// The text printed by `wakeloop hook-snippet`.
    public static func json(for agent: String) -> String? {
        guard let events = events(for: agent) else { return nil }
        let entries = events.map { "    \"\($0)\": [{ \"hooks\": [{ \"type\": \"command\", \"command\": \"\(command)\", \"timeout\": 5 }] }]" }
        return "{\n  \"hooks\": {\n" + entries.joined(separator: ",\n") + "\n  }\n}"
    }
}
