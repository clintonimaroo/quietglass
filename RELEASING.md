# Releasing QuietGlass

Release builds support macOS 14 or later on Apple silicon and Intel. Keep the bundle identifier stable so updates retain the app’s preferences. Changing the signing identity can require users to approve permissions or Keychain access again.

## Build and package

Use Xcode 26 or later and Python 3.11 or later. Check the latest published GitHub release and its packaged `Info.plist` before choosing the next version and build. Public release numbers follow the last published release: 0.1.0 (build 1) is followed by 0.1.1 (build 2). Local development iterations are not published release numbers. Set `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist` before building. Do not replace assets on a published version with a different build.

```sh
swift test
QUIETGLASS_UNIVERSAL=1 bash build.sh /tmp/QuietGlass-release/QuietGlass.app

python3 -m venv /tmp/quietglass-release-tools
/tmp/quietglass-release-tools/bin/python -m pip install -r scripts/release-requirements.txt
/tmp/quietglass-release-tools/bin/python scripts/package-release.py \
  --app /tmp/QuietGlass-release/QuietGlass.app \
  --output dist
```

Use an empty output directory. The packager produces a drag-to-Applications DMG, a ZIP with installation instructions, SHA-256 checksums, and `PACKAGE-INFO.json`. It verifies both executable architectures, signatures, required resources, ZIP integrity, and the app extracted from each container. A missing model, invalid signature, architecture mismatch, or stale version stops packaging.

## Developer ID and notarization

For distribution without the unidentified-developer warning, use an active Apple Developer Program membership and an installed **Developer ID Application** identity. Set `QUIETGLASS_SIGN_IDENTITY` to that identity before building. The build enables hardened runtime, a secure timestamp, and the camera entitlement. It also includes the App Intents metadata when the signing identity has an Apple Team ID.

Configure notarization credentials directly in your macOS Keychain with `xcrun notarytool store-credentials`. Do not place passwords or private keys in the repository or release directory.

```sh
export QUIETGLASS_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
QUIETGLASS_UNIVERSAL=1 bash build.sh /tmp/QuietGlass-release/QuietGlass.app

/tmp/quietglass-release-tools/bin/python scripts/package-release.py \
  --app /tmp/QuietGlass-release/QuietGlass.app \
  --output dist \
  --notary-profile QuietGlass-Notary
```

The packager submits the app and disk image to Apple, requires acceptance, staples and validates both tickets, and checks Gatekeeper. It refuses to label a local signature as notarized. A locally signed package includes Apple’s first-launch instructions instead.

## Verify and publish

- Check About, Settings, offline Help, first-launch permissions, and Escape in the packaged app.
- Exercise window/area blur and Focus while switching apps. Check head calibration and camera prompts with the relevant hardware.
- Confirm the app opens from Applications after copying from the DMG, including on another Mac. Record the hardware and macOS versions used; automated checks do not substitute for hardware checks.
- Review `PACKAGE-INFO.json` and run `shasum -a 256 -c SHA256SUMS` in the output directory.
- Commit the source, tag that commit with the version, and attach the DMG, ZIP, and checksums to its GitHub release. Do not publish signing keys, credentials, user preferences, face templates, or development logs.

Keep the preceding release available for rollback. GitHub downloads in a private repository require repository access; use a public release location or share the package directly with recipients.

## Updates and performance checks

The app checks GitHub's public latest-release endpoint, validates a stable semantic version and the repository's release URL, and offers the download page. Automatic checks are optional and run no more than daily, checked on startup, activation, and an hourly background timer. No tokens or user content are sent. Installation remains manual. A Sparkle installer requires a signed update archive, embedded public key, and published appcast; do not advertise automatic installation until that distribution path is configured and verified. See [Sparkle setup](https://sparkle-project.org/documentation/).

Run `QUIETGLASS_PROFILE=1 swift test -c release --filter PerformanceMeasurementTests` to measure the local detection, landmark, embedding, blur, OCR, and unchanged-frame checking costs using bundled fixtures. These timings are not battery-life or camera-accuracy measurements. Recheck responsiveness with real camera movement, multiple displays, and physical Space swipes before claiming those configurations are verified.
