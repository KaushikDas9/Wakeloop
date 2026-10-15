# Homebrew packaging

`wakeloop.rb` is a source-built Homebrew formula. It compiles Wakeloop on the user's Mac with `swift build -c release`, installs the `wakeloop` CLI on the PATH, and keeps `Wakeloop.app` inside the formula's prefix.

No Apple signing is involved. The app is built locally with an ad-hoc signature, so it is not quarantined and Gatekeeper does not block it. The first-launch steps in the main README are only needed for downloaded builds.

## How a tap works

Homebrew installs formulas from "taps", which are Git repositories. A tap named `KaushikDas9/wakeloop` is the GitHub repository `KaushikDas9/homebrew-wakeloop`, with the formula at `Formula/wakeloop.rb`. Users run:

```sh
brew tap KaushikDas9/wakeloop
brew install wakeloop
```

The `homebrew-` prefix is required for the short tap name. The formula in this folder is the file that goes into that repository. The main Wakeloop repository does not need to be a tap.

## Steps for the owner (by hand)

These steps touch GitHub, so they are not automated.

1. Create a public GitHub repository named `homebrew-wakeloop` under `KaushikDas9`. Add a short README and an MIT license if you want one.
2. Copy the formula into it:
   ```sh
   mkdir -p Formula
   cp /path/to/Wakeloop/packaging/homebrew/wakeloop.rb Formula/wakeloop.rb
   git add Formula/wakeloop.rb && git commit -m "Add wakeloop formula" && git push
   ```
3. Check it on a Mac with Xcode 15 or later installed:
   ```sh
   brew tap KaushikDas9/wakeloop
   brew install wakeloop
   brew test wakeloop
   brew audit --strict --formula wakeloop
   ```
4. Only after the tap is published, add the install commands to the main README (the README already has a placeholder section that says this).

## Version bumps

For each release, in `Formula/wakeloop.rb` in the tap repo (and in the copy in this folder, which should match):

1. Tag the release in the main repository, for example `v0.2.0`, and push the tag.
2. Download the tag tarball and compute its checksum. Use the real output, never a guessed value:
   ```sh
   curl -sSL -o wakeloop.tar.gz https://github.com/KaushikDas9/Wakeloop/archive/refs/tags/v0.2.0.tar.gz
   shasum -a 256 wakeloop.tar.gz
   ```
3. Update `url` to the new tag and `sha256` to the checksum.
4. Update the version string in the formula's `Info.plist` template only if it is no longer `0.1.0`. HEAD builds use that fixed string.
5. Run `brew style` and `brew audit --strict --formula` again, then commit.

The `v0.1.0` tarball predates the max-hold and crashed-session features and the app icon. The formula handles a missing icon, so `v0.1.0` still builds. `brew install --HEAD wakeloop` always builds the latest `main` branch.

## Caveats

- Building needs Xcode 15 or later (`depends_on xcode`). A Command Line Tools-only Mac is not enough for this formula.
- macOS 13 or later is required (`depends_on macos: :ventura`, from `Package.swift`).
- The app is not in `/Applications` after `brew install`. The formula's caveats show how to link it there. Check first that `/Applications/Wakeloop.app` does not already exist, so the link does not overwrite or land inside your existing copy.
- Because the app is built on the user's Mac, it is not notarized and has no Developer ID. That is intended: a locally built app is not quarantined, so Gatekeeper does not warn on first launch.
- The formula does not edit Claude Code settings. Run `wakeloop hook-snippet claude` and merge the output by hand, as in the main README.

## Local checks

`brew style packaging/homebrew/wakeloop.rb` passes. `brew audit` and `brew install` need a Mac with a complete Xcode installation, and the owner should run them before publishing.
