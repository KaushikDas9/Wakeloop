# Claude Code Hook Config

Verified against https://code.claude.com/docs/en/hooks on 2026-10-08. Formats change between versions; re-verify before relying on it.

## Facts that matter

- HTTP hooks receive the same JSON as command hooks, as a POST body. Common fields: `session_id`, `cwd`, `transcript_path`, `hook_event_name`.
- `Notification` carries `notification_type`: `permission_prompt`, `idle_prompt`, `agent_needs_input`, `agent_completed`, `quota_auto_resume_fired|stale|disabled` (v2.1.234+), and others.
- `StopFailure` carries `error` (`rate_limit`, `overloaded`, ...).
- The server must answer 2xx with an empty body or a JSON object. Non-2xx or connection failure is a non-blocking error, so the agent keeps running if Wakeloop is not open.
- Default HTTP hook timeout is 600 s.

## settings.json snippet (`~/.claude/settings.json`)

```json
{
  "hooks": {
    "SessionStart":      [{ "hooks": [{ "type": "http", "url": "http://127.0.0.1:47821/event", "timeout": 5 }] }],
    "UserPromptSubmit":  [{ "hooks": [{ "type": "http", "url": "http://127.0.0.1:47821/event", "timeout": 5 }] }],
    "Stop":              [{ "hooks": [{ "type": "http", "url": "http://127.0.0.1:47821/event", "timeout": 5 }] }],
    "StopFailure":       [{ "hooks": [{ "type": "http", "url": "http://127.0.0.1:47821/event", "timeout": 5 }] }],
    "Notification":      [{ "hooks": [{ "type": "http", "url": "http://127.0.0.1:47821/event", "timeout": 5 }] }],
    "PermissionRequest": [{ "hooks": [{ "type": "http", "url": "http://127.0.0.1:47821/event", "timeout": 5 }] }],
    "SessionEnd":        [{ "hooks": [{ "type": "http", "url": "http://127.0.0.1:47821/event", "timeout": 5 }] }]
  }
}
```

Merge into any existing `hooks` block rather than replacing it.
