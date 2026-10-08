# Agent Detection

Layered, most reliable first.

## 1. Hooks

Claude Code fires events the app can listen to. Verified in the hooks reference:

- `UserPromptSubmit`, `Stop`, `SessionStart`, `SessionEnd`
- `StopFailure` (matcher values include `rate_limit`)
- `Notification` (types include `permission_prompt`, `idle_prompt`, `agent_needs_input`, `agent_completed`, `quota_auto_resume_fired`, `quota_auto_resume_stale`, `quota_auto_resume_disabled`)
- `PermissionRequest`

Hooks can be shell commands or HTTP POSTs to a local endpoint. Codex has a `notify` setting and a `PermissionRequest` hook.

## 2. Process tree

Watch child processes the agent started (builds, tests) so a long silent command keeps the hold.

## 3. Session files

Read modification times and sizes (never contents) of transcript folders as a fallback for agents without hooks.

## States

working / waiting for you / idle. "Waiting" has a grace period (default 5 min) before sleep is allowed.

## Known hard cases

From Belay's changelog: silent tool calls, overloaded-model retries, background jobs. These are where reliability is won or lost.

> Hook formats change between versions. Re-verify each agent's current docs before building its detector.

## Codex

Verified against the Codex hooks docs (2026-10-08). Events: `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`, `SubagentStart`, `SubagentStop`, `Stop`, `Interrupt`. Every command hook gets JSON on stdin with `session_id` and `hook_event_name`, so `HookPayload` parses it unchanged. `Interrupt` is treated like `Stop`.

Setup: `wakeloop hook-snippet codex` prints a config to merge into `~/.codex/hooks.json` (or `<repo>/.codex/hooks.json`). Codex only runs non-managed hooks after you review and trust them with `/hooks`.

Not yet tested against a live Codex run. Subagent events reuse the parent session ID, so they are ignored for now.
