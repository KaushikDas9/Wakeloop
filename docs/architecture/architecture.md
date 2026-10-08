# Architecture (proposed)

```
Agent hooks / process watcher / session files
              | state events (file, socket, local HTTP)
              v
      Wakeloop menu bar app  (Swift, SwiftUI/AppKit)
        - state engine         - power manager (IOKit assertions)
        - battery / thermal    - notifications, settings
              | XPC (optional)
              v
   Privileged helper (one command: pmset disablesleep)
```

## Decisions

- **Swift** for the app: native power and menu bar APIs; Electron/Tauri are a poor fit.
- **IOKit power assertions** for idle sleep. They do **not** keep a lid-closed Mac awake.
- **Helper** flips `pmset disablesleep` for lid-closed, with a heartbeat watchdog that restores normal sleep if the app stops checking in (the pattern Lidless and Vigil use). See [lid-closed](lid-closed.md).
- **CLI** (`wakeloop hold --for 30m`, `wakeloop done`) so agents and scripts can talk to the app.
- Detectors stay modular and tested, since agent formats change (see [agent-detection](agent-detection.md)).
