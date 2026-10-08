# MVP Scope

Core behavior (table stakes, every competitor has these):

- Menu bar app with on / off / auto modes.
- Hold the Mac awake only while at least one agent session is **working**.
- Detect agent state: working / waiting for you / idle (see [agent-detection](../architecture/agent-detection.md)).
- "Waiting for you" grace period (default 5 min, configurable), then allow sleep.
- Battery floor: sleep at 20%, resume at 25% or when plugged in.
- Heat guard: always allow sleep when the Mac is too hot, with a notification.
- Pause (30 min / 1 hour / until tomorrow), keyboard shortcuts, launch at login.
- Lid-closed support via a minimal privileged helper (see [lid-closed](../architecture/lid-closed.md)).
- CLI: `wakeloop hold --for 30m`, `wakeloop done`, so agents and scripts can talk to the app.

## Out of scope for MVP

Phone control, stuck-agent detection, auto-checkpoint, multi-machine view, non-Mac platforms. See [differentiation](differentiation.md).
