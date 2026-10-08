# Differentiation: Hypotheses to Test

None of these is proven to be wanted. Each needs a quick spike and a demand check.

1. **Hold during Claude Code's own auto-continue wait.** (Checked 2026-10-08: the `quota_auto_resume_*` notifications fire when the wait ENDS (`fired` = continued, `stale` = reset happened while the Mac slept >30 min, `disabled` = gave up), not when it starts. Holding through the wait needs a start signal; `StopFailure` with the `rate_limit` matcher is the likely candidate but its payload is unverified. `fired`/`stale`/`disabled` are already mapped in `HookPayload` so auto-continued work counts as working.) Claude Code can wait for a usage limit to reset and continue by itself, but only if the session is open (and, presumably, the Mac is awake). Listen for the `quota_auto_resume_*` notification events and hold the Mac awake (or schedule a wake with `pmset schedule wake`). Small and easy to copy: a feature, not a business.
2. **Two-way phone control.** The `PermissionRequest` hook can allow or deny, and HTTP hooks wait up to 10 minutes by default, so approving a prompt from a phone is technically straightforward. First-party Remote Control and Codex remote already exist; test whether people want a cross-agent, self-hosted version.
3. **Stuck-agent detection.** Warn when CPU is busy but no files or transcripts change for a long time. No competitor was found offering this (based on the pages read).
4. **Auto-checkpoint.** Git commit or stash when an agent goes idle.
5. **Multi-machine view** (laptop plus a home server).
6. **Reliability as the feature.** Belay's changelog shows detection edge cases (silent tool calls, overloaded-model retries, background jobs) are the hard part. Excellent, well-tested detection plus a clear "why is my Mac awake" panel can beat feature count.
7. **Non-Mac platforms.** Every competitor found is Mac-only.

## First step

Install Adrafinil, Belay and Vigil, use them for a week with real agent runs, and write down what breaks or is missing. Build what you personally hit.
