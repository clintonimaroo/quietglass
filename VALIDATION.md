# Validation — September 19, 2026

## Passed

- `swift test`: 10 tests, 0 failures. Covers thresholds, Escape suppression/rearming, recenter, ±180° wraparound, head nod versus sideways tilt, invalid angle input, directional mask feathering, full/zero coverage, frame-rate-independent spring motion, and smooth reversal/reset.
- Final release build compiled successfully on this Apple silicon Mac.
- `Info.plist` validation passed; includes the Motion usage description and macOS 14 minimum.
- The rebuilt app launched as a 40 × 8-point resting dash inside a 44 × 12-point panel, without the former full settings window. The resting state and expanded 116 × 30-point row of three black Hugeicons buttons were visually inspected.
- Right-clicking both the resting dash and expanded controls opened the native context menu. Settings opened the controls popover. Its accessibility tree exposed Start/Pause, Recenter, the screen permission action, both primary sliders, More, and Preview blur. Previously saved movement sensitivity was retained.
- More expanded to expose the transition slider and custom recenter shortcut. The notch was observed returning to its collapsed state after pointer interaction ended.
- All app-owned icons were replaced with geometry from the MIT-licensed Hugeicons free set. No `systemName`, `systemImage`, or `systemSymbolName` calls remain in the source. The notice is packaged with the app.
- The final app zip was extracted to a temporary directory and passed `codesign --verify --strict --verbose=2`. The Hugeicons license was present in the extracted app.
- Earlier live checks in this development session observed AirPods motion, calibration, head-triggered coverage, and Escape dismissal. These were performed before the final notch/icon rebuild.

## Remaining verification

- **Final display blur:** macOS reports Screen Recording permission as unavailable for the rebuilt app. The Gaussian renderer compiles, but its final live appearance still needs verification after QuietGlass is reapproved. The current app keeps the screen clear and opens setup from the tracking button until access is available; it does not substitute a white/gray cover.
- The final notch's drag/persistent-position behavior, one-hour snooze expiry, full keyboard navigation, and popover/tooltip layout across display configurations need broader interaction testing. The floating label and right-click menu use separate native windows that the UI capture tool could not include in the notch screenshot; menu entries and actions were verified through accessibility.
- Multiple displays, full-screen apps/Spaces, actual sleep/wake, and swapping the active earbud were implemented but not exhaustively exercised on hardware.
- This is an independent implementation inspired by public demonstrations, not the original creator's private source or an exact optical reproduction.

## Packaging

`build.sh` verifies the locally signed bundle before archiving. Signing and archiving happen in a temporary directory because Documents sync can add Finder metadata to unpacked bundles. Use the supplied zip for installation into Applications.

The app starts paused after relaunch. macOS manages Motion & Fitness and Screen Recording approvals; they are not granted automatically.
