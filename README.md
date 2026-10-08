# Wakeloop

A macOS menu bar app that keeps your Mac awake **only while an AI coding agent is working**, then lets it sleep.

> **Status: early prototype.** The code builds and the unit tests pass, but nothing has been tested end to end on real agent runs yet. See [the live test checklist](docs/testing/live-test-checklist.md).

## What it does

- Holds the Mac awake while a Claude Code or Codex session is working (detected through agent hooks).
- Keeps holding while an agent's child process is busy, such as a long build or test run.
- Gives a "waiting for you" grace period (default 5 minutes), then allows sleep.
- Always allows sleep on low battery (floor 20%, resumes at 25%) or when the Mac is too hot.
- Menu bar modes: Auto, Always on, Off. Pause for 30 minutes, 1 hour or until tomorrow.
- Global shortcuts: `Ctrl+Opt+Cmd+P` pause or resume, `Ctrl+Opt+Cmd+M` cycle mode.
- "Why is my Mac awake" window, including every other app's sleep assertions.
- Optional lid-closed mode (off by default, needs a one-time setup).
- CLI: `wakeloop hold --for 30m`, `wakeloop done`.

## Build and run

Requires macOS 13+ and Swift 5.9+.

```sh
swift test                  # run unit tests
scripts/build-app.sh        # builds dist/Wakeloop.app (ad-hoc signed)
open dist/Wakeloop.app
```

The CLI is inside the bundle at `Wakeloop.app/Contents/Resources/bin/wakeloop`. Unsigned builds may need approval in System Settings, Privacy & Security.

## Connect your agents

Wakeloop listens on `127.0.0.1:47821`. Print a hooks config and merge it by hand (Wakeloop never edits your agent config):

```sh
wakeloop hook-snippet claude    # for Claude Code settings
wakeloop hook-snippet codex     # for ~/.codex/hooks.json; trust it with /hooks in Codex
```

## Lid-closed mode

Power assertions alone do not keep a lid-closed Mac awake. Wakeloop uses `pmset disablesleep`, which needs root. Run `wakeloop lid-setup` to print the exact one-time `sudoers` rule (two commands only), then enable "Keep awake with lid closed" in the menu. A watchdog restores normal sleep if the app quits or crashes. Do not put a working Mac in a closed bag.

## Docs

Product, architecture, research and roadmap live in [`docs/`](docs/README.md).

## License

Not decided yet. No license is granted until one is added.
