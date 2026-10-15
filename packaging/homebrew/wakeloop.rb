# frozen_string_literal: true

# Source-built Homebrew formula for Wakeloop. No Apple signing or notarization:
# it compiles locally, so the resulting app is not quarantined and Gatekeeper
# does not block it.
#
# This file is meant to live in a tap repo named homebrew-wakeloop at
# Formula/wakeloop.rb. See packaging/homebrew/README.md in the main repo.
#
# BUMP FOR EACH RELEASE: change `url` to the new tag tarball, update `sha256`
# (shasum -a 256 on the downloaded tarball, never a guessed value), and keep
# the version string in the app bundle plist below in step.
#
# NOTE: the v0.1.0 tarball predates recent features (max hold, crashed-session
# expiry, app icon). It has no assets/AppIcon.icns, so this formula copies the
# icon only when the file exists. `brew install --HEAD wakeloop` builds main.
class Wakeloop < Formula
  desc "Keep a Mac awake only while Claude Code is working"
  homepage "https://github.com/KaushikDas9/Wakeloop"
  url "https://github.com/KaushikDas9/Wakeloop/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "433d0ae500c8e9c1c27ebced21b6a499c04a67ee737d67ae6eab4874e2e5afa4"
  license "MIT"
  head "https://github.com/KaushikDas9/Wakeloop.git", branch: "main"

  depends_on xcode: ["15.0", :build] # Swift 5.9 toolchain needs Xcode 15 or later
  depends_on macos: :ventura # macOS 13, from platforms in Package.swift

  def install
    # Homebrew's sandbox blocks the nested sandbox SwiftPM would create.
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin_path = Utils.safe_popen_read(
      "swift", "build", "--disable-sandbox", "-c", "release", "--show-bin-path"
    ).chomp

    # CLI goes on PATH.
    bin.install "#{bin_path}/wakeloop"

    # Same bundle layout as scripts/build-app.sh: the CLI lives in
    # Resources/bin because the filesystem is case-insensitive.
    app = buildpath/"dist/Wakeloop.app"
    (app/"Contents/MacOS").mkpath
    (app/"Contents/Resources/bin").mkpath
    cp "#{bin_path}/WakeloopApp", app/"Contents/MacOS/Wakeloop"
    cp "#{bin_path}/wakeloop", app/"Contents/Resources/bin/wakeloop"
    icon = buildpath/"assets/AppIcon.icns"
    cp icon, app/"Contents/Resources/AppIcon.icns" if icon.exist?
    # HEAD builds report the last stable version, since "HEAD" is not a valid bundle version.
    short_version = build.head? ? "0.1.0" : version.to_s
    (app/"Contents/Info.plist").write <<~PLIST
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>app.wakeloop.Wakeloop</string>
        <key>CFBundleName</key><string>Wakeloop</string>
        <key>CFBundleExecutable</key><string>Wakeloop</string>
        <key>CFBundleIconFile</key><string>AppIcon</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        <key>CFBundleShortVersionString</key><string>#{short_version}</string>
        <key>CFBundleVersion</key><string>1</string>
        <key>LSMinimumSystemVersion</key><string>13.0</string>
        <key>LSUIElement</key><true/>
      </dict></plist>
    PLIST
    # Ad-hoc signature, as build-app.sh does. No Developer ID is involved.
    system "codesign", "--force", "--sign", "-", app

    # The app stays in the keg; caveats explain how to link it into /Applications.
    prefix.install app
  end

  def caveats
    <<~EOS
      Wakeloop.app is installed inside the formula, not in /Applications:
        #{opt_prefix}/Wakeloop.app

      To add it to /Applications (skip this if you already have a Wakeloop.app there):
        ln -s "#{opt_prefix}/Wakeloop.app" /Applications/

      Or open it directly:
        open "#{opt_prefix}/Wakeloop.app"

      The app must be running for the wakeloop CLI to work. Connect Claude Code with:
        wakeloop hook-snippet claude
      and merge the output into your Claude Code settings by hand.
    EOS
  end

  test do
    # Offline: prints a hooks config and does not contact the app.
    assert_match "SessionStart", shell_output("#{bin}/wakeloop hook-snippet claude")
    # Unknown or missing commands print usage and exit 2.
    assert_match "usage:", shell_output("#{bin}/wakeloop --help", 2)
  end
end
