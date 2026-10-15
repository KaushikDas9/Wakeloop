# Wakeloop

**Keep your Mac awake while your AI coding agent works. Let it sleep when it's done.**

Start a long task in Claude Code, close the lid, and walk away. Wakeloop keeps your Mac awake only while the agent is busy, then lets it sleep. A small macOS menu bar app. Free and open source.

[Website](https://kaushikdas9.github.io/Wakeloop/) · [Full guide](GUIDE.md) · [Report a bug](https://github.com/KaushikDas9/Wakeloop/issues)

![Wakeloop: keep your Mac awake only while Claude Code is working](assets/hero.svg)

## Why

Your Mac goes to sleep and the agent stalls halfway through a task. `caffeinate` fixes that, but it also keeps the Mac awake long after the agent has finished. Wakeloop holds the Mac awake only while the agent is actually working.

## Quick start

You need a Mac running macOS 13 or later, and Xcode (or the Swift toolchain) to build it.

**1. Build and open the app**

```sh
git clone https://github.com/KaushikDas9/Wakeloop.git
cd Wakeloop
scripts/build-app.sh
open dist/Wakeloop.app
```

A small ring appears in your menu bar.

**2. Connect Claude Code**

A setup guide opens the first time. Click **Set up** next to *Claude Code hooks*. Wakeloop backs up your settings file and adds its entries. Nothing else is changed.

**3. Use Claude Code as normal**

Send a prompt. The ring pulses while Claude works, and your Mac stays awake. When Claude finishes, the ring calms down and your Mac can sleep.

That's it. For closing the lid, see [lid-closed mode](GUIDE.md#lid-closed-mode).

## What you see

![Illustration of the Wakeloop menu: three agents working, with sub-agents under their project](assets/menu-mock.svg)

*Illustration, not a screenshot.*

The menu shows which projects are working. You can pause, switch modes, and ask "Why is my Mac awake?" at any time.

## Safe by default

- Sleep is allowed when the battery is low (20%) or the Mac gets too hot.
- A hold ends after 8 hours with no agent activity, and crashed sessions expire.
- Wakeloop edits your agent settings only when you ask, and backs them up first.
- No account, no telemetry. Everything runs on your Mac.
- Lid-closed mode is optional and off by default. Do not put a working Mac in a closed bag.

## Status

An early pre-release (v0.1.0). It works with **Claude Code**. Codex setup is built but not tested yet, so it isn't supported. The app is not notarized by Apple, so a downloaded copy needs right-click, then **Open**, the first time. An app you build yourself opens normally. Details are in the [guide](GUIDE.md#status-and-testing).

## Learn more

[GUIDE.md](GUIDE.md) covers the menu, every setting, Codex, Homebrew, lid-closed mode, the command line and the safety rules.

## Support

Free and open source under the [MIT License](LICENSE). Bug reports and pull requests are welcome (run `swift test` first). If Wakeloop is useful to you, a star helps others find it, and you can [buy me a coffee on Ko-fi](https://ko-fi.com/koushikdas).
