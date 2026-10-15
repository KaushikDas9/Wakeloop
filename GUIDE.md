# Wakeloop guide

The full reference. For a quick start, see the [README](README.md).

## Contents

- [The menu](#the-menu)
- [Install options](#install-options)
- [Connect your agent](#connect-your-agent)
- [All features](#all-features)
- [Safety](#safety)
- [Lid-closed mode](#lid-closed-mode)
- [Command line](#command-line)
- [Status and testing](#status-and-testing)

## The menu

![Illustration of the Wakeloop dropdown: three agents working, with sub-agents listed under their project](assets/menu-mock.svg)

*Illustration, not a screenshot.*

The menu bar shows a small ring. While Wakeloop is not holding the Mac awake, the ring stays calm. While it is holding, the ring pulses and a count of working agents sits beside it.

The dropdown starts with a status line, then a "Working now" list of projects. A project with sub-agents expands into a tree. Click a project to expand or collapse it. Below the list:

- **Mode**: Auto, Always on (for example, Remote Control), or Off.
- **Pause**: 30 minutes, 1 hour, until tomorrow, or Resume now.
- **Why is my Mac awake…**: a report of Wakeloop's state and every sleep assertion on the Mac.
- **Settings**: Show setup guide, Sleep after, Max hold, Claude Code hooks, Codex hooks, Launch at login, and Lid-closed mode.
- **Quit Wakeloop**

On macOS 14.4 and later, some items show a short grey subtitle.

## Install options

Requires macOS 13 or later. Building needs Swift 5.9 or later (Xcode 15 or a matching Swift toolchain).

### Build from source (works today)

```sh
git clone https://github.com/KaushikDas9/Wakeloop.git
cd Wakeloop
scripts/build-app.sh
open dist/Wakeloop.app
```

An app you build on your own Mac is not quarantined, so it opens normally.

### A downloaded copy

Builds are ad-hoc signed and **not notarized by Apple**, because that needs a paid Apple Developer membership. A prebuilt copy you download is quarantined, and macOS blocks its first launch. To allow it:

- Right-click (or Control-click) `Wakeloop.app`, choose **Open**, then click **Open**; or
- Go to **System Settings > Privacy & Security** and click **Open Anyway**.

Only do this for a build from a source you trust.

### Homebrew (not available yet)

A source-built formula is prepared in [`packaging/homebrew/`](packaging/homebrew/README.md). It works only after the tap repository `KaushikDas9/homebrew-wakeloop` is published.

## Connect your agent

Wakeloop learns what your agent is doing from hooks. The first time you open the app, a setup guide walks you through it. You can reopen it from **Settings > Show setup guide…**.

### Claude Code

Open **Settings > Set up Claude Code hooks…**. Wakeloop shows what it will change and asks you to confirm. It adds its hook entries to `~/.claude/settings.json`, keeps your other hooks where they are, and saves a timestamped backup next to the file first. Running it again changes nothing. **Remove Claude Code hooks…** removes only Wakeloop's own entries.

If your settings file is not valid JSON, or it is read-only, Wakeloop refuses to touch it and tells you why.

Prefer to do it by hand? Print the config and merge it yourself:

```sh
wakeloop hook-snippet claude
```

### Codex (built, not yet live-tested)

**Settings > Set up Codex hooks…** adds Wakeloop's entries to `~/.codex/hooks.json`, with the same safety rules. Codex also needs you to trust new hooks: open Codex, run `/hooks`, and trust Wakeloop's entries. Codex is not a supported agent until it has been tested with a live session.

```sh
wakeloop hook-snippet codex
```

### If the hooks are missing

Wakeloop falls back to watching recently written session transcripts and busy child processes. This works, but it sees sessions later and less reliably.

## All features

- Holds the Mac awake while a Claude Code session is working. In Auto mode it also keeps holding while a child process of the agent is busy, such as a long build or test run.
- Counts working agents in the menu bar, with project names and sub-agents under each project.
- Modes: Auto (default), Always on, and Off.
- Pause for 30 minutes, 1 hour, or until 6 a.m. the next day.
- "Sleep after": how long the Mac stays awake when Claude is waiting for you, for example at a permission prompt. Default 5 minutes; choose 1, 5, 10, 15 or 30.
- Shortcuts: `Ctrl+Opt+Cmd+P` pauses or resumes, and `Ctrl+Opt+Cmd+M` cycles the mode.
- A "Why is my Mac awake" window that shows each session, busy processes, and every sleep assertion.
- First-run setup guide with live status and a "Connected" check.
- Launch at login.
- No account and no telemetry. Everything runs on your Mac.

## Safety

- **Battery:** sleep is allowed at 20% or lower on battery. The hold comes back at 25%, or when the charger is connected.
- **Heat:** sleep is allowed when the Mac is too hot, with a notification.
- **Max hold:** an automatic hold is released after 8 hours with no agent event or transcript write (Settings > Max hold: 4, 8, 12 hours or Off). A notification says so. The next agent event brings the hold back. Always on and manual holds are not capped.
- **Crashed sessions:** a working session with no hook event and no transcript write for 2 hours is dropped. A long silent command still holds through the process tree.
- **Sub-agents:** one whose transcript has not been written for 3 minutes is dropped. Any still listed after 1 hour is dropped too.
- **Your config:** Wakeloop changes `~/.claude/settings.json` or `~/.codex/hooks.json` only when you choose Set up or Remove. It backs the file up first and never overwrites a file it cannot parse.

## Lid-closed mode

Optional, and off by default. A normal sleep assertion does not keep a closed Mac awake, so Wakeloop uses `pmset disablesleep`, which needs administrator rights.

Open **Settings > Lid-closed mode…**:

- **Set up…** (the first time): Wakeloop explains what it will do, then macOS shows its standard password dialog. After that one approval, Wakeloop can turn sleep prevention on and off using only two `pmset` commands. The sudoers rule is checked with `visudo` before it is installed. A watchdog restores normal sleep if the app quits or crashes.
- **Keep awake with lid closed**: a switch.
- **Power source**: **Charger only** (default), or **Charger or battery** (stops at 30%, resumes at 35%). Choosing battery asks you to confirm.
- **Remove setup…**: removes the rule. To remove it by hand: `sudo rm /etc/sudoers.d/wakeloop`.

Prefer the terminal? `wakeloop lid-setup` prints the rule and the steps. It changes nothing itself.

**Warning:** do not put a working Mac in a closed bag.

## Command line

The `wakeloop` CLI is inside the app at `Wakeloop.app/Contents/Resources/bin/wakeloop`. The app must be running.

```sh
wakeloop hold --for 30m          # hold the Mac awake for a set time
wakeloop done                    # release a manual hold
wakeloop hook-snippet claude     # print the hooks config (or: codex)
wakeloop lid-setup               # print the lid-closed sudoers rule
```

## Status and testing

Wakeloop is an early pre-release (v0.1.0). The unit tests run with `swift test`.

- **Live-tested on the author's Mac:** building and launching, the hook server, Claude Code hooks, one-click hook setup and removal, the setup guide, the working count, project names, sub-agents, the menu, modes, lid-closed setup, and lid-closed mode on the charger.
- **Not yet live-tested:** Codex (setup, `/hooks` trust, holds, Stop and Esc release), the "Sleep after" timeout, max hold and crashed-session expiry, the battery guard, launch at login, the global shortcuts, lid-closed mode on battery, and process-tree behaviour.
