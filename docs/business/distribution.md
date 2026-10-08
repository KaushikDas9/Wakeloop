# Distribution (no App Store)

The Mac App Store sandbox blocks the helper, so ship directly from a website or GitHub.

## Free phase (no $99 certificate)

- Open-source repo; `git clone` then build script (locally built apps are not quarantined).
- Optional install script, ad-hoc signing.
- Tell downloaders to allow the app in System Settings, Privacy & Security.

## Signed phase

- Apple Developer Program ($99/year), Developer ID signing, notarization.
- Sparkle auto-updates, `.dmg`.
- Belay already ships notarized, so unsigned builds will look rough by comparison.

## Later

- Homebrew cask; check current policy on unsigned casks first.
- License: decide MIT vs source-available **before** publishing.
