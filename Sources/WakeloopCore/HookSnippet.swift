import Foundation

/// Wakeloop's hook entries for agents. The one source for `wakeloop hook-snippet` and the in-app installers.
public enum HookSnippet {
    /// Each hook POSTs its JSON to the app and ignores failures, so the agent is never blocked.
    public static let command = "curl -s -m 2 -X POST --data-binary @- http://127.0.0.1:\(wakeloopPort)/event >/dev/null || true"

    public static let claudeEvents = ["SessionStart", "UserPromptSubmit", "PermissionRequest", "Stop", "SessionEnd",
                                      "Notification", "SubagentStart", "SubagentStop"]
    /// Codex has no Notification event but has Interrupt (verified against the OpenAI Codex hooks docs).
    /// SubagentStart and SubagentStop exist in Codex too, but their payload fields are not verified, so they are left out.
    public static let codexEvents = ["SessionStart", "UserPromptSubmit", "PermissionRequest", "Stop", "SessionEnd", "Interrupt"]

    /// Claude Code allows a generous timeout. Codex documents a maximum of 3 seconds for SessionEnd and Interrupt,
    /// so every Codex entry uses 3. The curl itself gives up after 2 seconds.
    public static let claudeTimeout = 5
    public static let codexTimeout = 3

    public static func events(for agent: String) -> [String]? {
        switch agent {
        case "claude": return claudeEvents
        case "codex": return codexEvents
        default: return nil
        }
    }

    public static func timeout(for agent: String) -> Int? {
        switch agent {
        case "claude": return claudeTimeout
        case "codex": return codexTimeout
        default: return nil
        }
    }

    /// One hook group, in the shape Claude Code's settings and Codex's hooks.json both use.
    public static func group(timeout: Int = claudeTimeout) -> [String: Any] {
        ["hooks": [["type": "command", "command": command, "timeout": timeout]]]
    }

    /// The text printed by `wakeloop hook-snippet`.
    public static func json(for agent: String) -> String? {
        guard let events = events(for: agent), let timeout = timeout(for: agent) else { return nil }
        let entries = events.map { "    \"\($0)\": [{ \"hooks\": [{ \"type\": \"command\", \"command\": \"\(command)\", \"timeout\": \(timeout) }] }]" }
        return "{\n  \"hooks\": {\n" + entries.joined(separator: ",\n") + "\n  }\n}"
    }
}
