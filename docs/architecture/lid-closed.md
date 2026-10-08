# Lid-Closed Behavior (main technical risk)

- Power assertions alone will not keep a lid-closed Mac awake; `pmset disablesleep` is the mechanism the other apps use.
- On Apple Silicon, lid-close sleep is partly hardware-gated. Reliability is highest on power and/or with an external display. Test on your own Mac first (adapter and battery).
- The helper needs one-time user approval. Keep it minimal (one command), document it, and add a watchdog so the Mac can never get stuck awake.
- Free-phase workaround without an Apple certificate: support the adapter case only, or use a clearly explained scoped `sudoers` rule for exactly the two `pmset` commands.
- Always warn: do not put a working Mac in a closed bag. Always sleep on low battery or high heat.

## Spike checklist (M0)

- [ ] Does a power assertion alone hold the Mac awake lid-closed on the adapter on your macOS version?
- [ ] Does `pmset disablesleep 1` hold on battery? On adapter? With external display?
- [ ] Watchdog restores normal sleep when the app is killed.
- [ ] Can the sudoers route replace the helper without hurting reliability?
