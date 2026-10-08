# Live test checklist

Nothing below has been run yet. Tick as you go and note the macOS version and Mac model.

## Setup
- [ ] `swift test` passes
- [ ] `scripts/build-app.sh` then `open dist/Wakeloop.app`; menu bar shows "○ Wakeloop"
- [ ] `curl -X POST localhost:47821/done` returns `{}` (server is up)

## Claude Code hooks
- [ ] Merge `wakeloop hook-snippet claude` into Claude Code settings
- [ ] Submit a prompt: icon turns "●", `pmset -g assertions` lists Wakeloop
- [ ] Task finishes (Stop): hold releases
- [ ] Permission prompt: state becomes waiting; hold releases after the grace period
- [ ] Two sessions at once: hold lasts until both stop

## Codex hooks
- [ ] Merge `wakeloop hook-snippet codex` into `~/.codex/hooks.json`; trust it with `/hooks`
- [ ] Prompt holds, Stop releases, Esc (Interrupt) releases
- [ ] Confirm the payload really has `hook_event_name` and `session_id` (log one with `nc -l 47821` while Wakeloop is quit)

## Process tree
- [ ] Ask an agent to run a 2 minute CPU-heavy command; hold stays after hooks say idle; status reads "Background work"
- [ ] Idle MCP servers do NOT hold the Mac awake
- [ ] Check the 3% CPU threshold is sensible; check agents that run as `node`

## Guards, modes, pause
- [ ] Battery under 20% on battery: hold releases and a notification appears; resumes at 25% or on AC
- [ ] Always on holds; Off never holds; Pause 30 min releases and "Resume now" works
- [ ] Both shortcuts work; note any conflict with other apps
- [ ] Grace period choice survives relaunch

## Lid-closed (risky: keep the Mac on a desk)
- [ ] `wakeloop lid-setup`, add the sudoers rule, `sudo visudo -c`
- [ ] Enable the toggle with a working agent: `pmset -g | grep SleepDisabled` shows 1
- [ ] Close the lid on the adapter: Mac stays awake
- [ ] Close the lid on battery: note the result (Apple Silicon may differ)
- [ ] Close the lid with an external display: note the result
- [ ] Agent stops: `SleepDisabled` returns to 0
- [ ] `kill -9` the app: SleepDisabled returns to 0 within about 10 seconds
- [ ] Quit from the menu: SleepDisabled returns to 0
- [ ] Without the sudoers rule: notification explains the setup, no retry spam

## Why-awake window and bundle
- [ ] Window shows sessions, busy processes and assertions
- [ ] Launch at login works from the bundle (may need approval in Login Items)
- [ ] Notifications appear from the bundle

## Session-file fallback
- [ ] With hooks removed, a working Claude Code or Codex session still holds the Mac awake (status: "Agent transcript was just written to")
- [ ] After the agent stops, the hold releases within about 20-25 seconds
- [ ] Check the scan does not use noticeable CPU with many projects in `~/.claude/projects`
