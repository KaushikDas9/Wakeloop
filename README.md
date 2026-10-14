# Wakeloop

A macOS menu bar app that keeps your Mac awake while an AI coding agent is working, then lets it sleep.

![Wakeloop: keep your Mac awake only while your AI agent is working](assets/hero.svg)

![Animated demo: the menu bar goes from ○ to ● 3 while agents work, then back to ○ when they finish](assets/wakeloop-demo.gif)

*Illustrated demo, not a screen recording.*

## The problem

You start a long task in Claude Code and walk away. The Mac goes to sleep, and the agent stalls halfway through. The obvious fix is `caffeinate`, but then the Mac stays awake all night after the agent has finished. Wakeloop holds the Mac awake only for as long as an agent is busy.

## How it works

![Claude Code hooks send events to Wakeloop, which tracks each session and holds a macOS sleep assertion. Guards can allow sleep.](assets/how-it-works.svg)

1. Agent hooks send a small event to Wakeloop on `127.0.0.1:47821` whenever a session starts, takes a prompt, asks for permission, or stops.
2. Wakeloop keeps a table of sessions, each one working, waiting or idle. Sub-agents count as workers.
3. While anything is working, Wakeloop holds a macOS sleep assertion. When every session is idle, it releases the assertion and the Mac can sleep.

A session that is waiting for you keeps the Mac awake for a grace period (5 minutes by default). Guards always win: low battery, a hot Mac, or a pause releases the hold.

## What you see

![Illustration of the Wakeloop dropdown: three agents working, with sub-agents listed under their project](assets/menu-mock.svg)

*Illustration, not a screenshot.*

The menu bar shows `○` when nothing is holding the Mac awake and `●` when Wakeloop is holding it, with a count of working agents, for example `● 2 Wakeloop`. The dropdown lists each project with its sub-agents as an expandable tree, followed by the mode and pause controls.

## Quick start

Requires macOS 13 or later and Swift 5.9 or later.

1. **Build**

   ```sh
   swift test              # run the unit tests
   scripts/build-app.sh    # builds dist/Wakeloop.app
   ```

2. **Open**

   ```sh
   open dist/Wakeloop.app
   ```

   The build is ad-hoc signed. If macOS blocks it, approve it in System Settings, Privacy & Security.

3. **Connect Claude Code**

   ```sh
   wakeloop hook-snippet claude
   ```

   This prints the hooks config for Claude Code settings. Merge it into your settings by hand. Wakeloop never edits your agent config. The `wakeloop` CLI is inside the bundle at `Wakeloop.app/Contents/Resources/bin/wakeloop`.

## Features

- Holds the Mac awake while a Claude Code or Codex session is working, and keeps holding while an agent's child process is busy, such as a long build or test run.
- Falls back to watching session transcript files if the hooks are missing.
- Modes: Auto, Always on, Off.
- Pause for 30 minutes, 1 hour, or until tomorrow.
- Shortcuts: `Ctrl+Opt+Cmd+P` pauses or resumes, `Ctrl+Opt+Cmd+M` cycles the mode.
- A "Why is my Mac awake" window that lists Wakeloop's holds and every other app's sleep assertions.
- CLI for scripts and agents: `wakeloop hold --for 30m` and `wakeloop done`.

## Safety

- Sleep is always allowed when the battery is below 20%, and the hold resumes at 25% or when the charger is connected.
- Sleep is always allowed when the Mac is too hot, with a notification.
- Wakeloop does not change your agent configuration. You merge the hooks yourself.

## Lid-closed mode (optional)

Lid-closed mode is off by default. Power assertions alone do not keep a closed Mac awake, so Wakeloop uses `pmset disablesleep`, which needs administrator rights.

Open **Settings > Lid-closed mode…** in the menu. The window has:

- **Set up…**, the first time. Wakeloop explains what it will do, then macOS shows its standard password dialog. After that one approval, Wakeloop can turn sleep prevention on and off by itself, and only for two commands. A watchdog restores normal sleep if the app quits or crashes.
- **Keep awake with lid closed**, a switch.
- **Power source**: **Charger only** (default), or **Charger or battery (stops at 30%)**. Choosing battery asks you to confirm first.
- **Remove setup…**, which undoes the setup.

Charger only is the default because lid-closed mode works only while the charger is connected. Prefer the terminal? `wakeloop lid-setup` prints the equivalent `sudoers` rule.

**Warning:** do not put a working Mac in a closed bag.

## Status

Wakeloop is an early prototype.

- Live-tested on the author's Mac: building and launching the app, the hook server, Claude Code hooks, the working-agent count, project names, and sub-agent tracking.
- Not yet live-tested: Codex hooks, lid-closed mode, the battery guard, launch at login, and process-tree behaviour (keeping the Mac awake while a child process runs).

The unit tests pass.

## License

Not decided yet. No license is granted until one is added.
