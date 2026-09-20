# QuietGlass

A tiny Mac notch that blurs your screen when you look away with AirPods. It keeps the desktop's colors and softens its details, with a feathered transition that follows your head movement.

## Start

1. Build the app, or unzip `QuietGlass.zip` and move the app to Applications.
2. Connect and wear compatible AirPods, then open QuietGlass. A thin 40 × 8-point dash appears above the Dock.
3. Hover over the dash to reveal three black buttons: tracking, recenter, and blur preview. Hover a button to see its label.
4. Right-click the notch and choose **Settings…** to allow Motion & Fitness and Screen Recording if needed. Start tracking, face the screen, and click **Recenter**.
5. Look away to blur the screen; look back to clear it. **Preview blur** runs for five seconds without AirPods.

**Escape** clears the blur immediately. The default recenter shortcut is **Control–Option–Command–C**, which also starts tracking if paused. Change it under **More** in the controls.

The dash morphs into the controls on hover and smoothly closes when the pointer leaves. Its drawing area stays in place until the closing animation finishes, including when the pointer returns mid-transition. It defaults to screen center, just above the Dock. Older development positions are reset on this update; drag it to save a custom position. **Move Notch to Bottom Center** restores the Dock placement. Right-click for **Hide for 1 hour**, **Settings…**, tracking, recenter, preview, and clear actions. The menu bar eye offers show/hide, position reset, controls, and quit. The app starts paused after launch and requires a new calibration. There is no main settings window.

Requires macOS 14 or later and AirPods 3/4, AirPods Pro, or AirPods Max. At least one compatible earbud must be worn. Permission settings are managed by macOS; a rebuilt, locally signed app may require renewed approval and a relaunch.

## Controls

| Control | Default | Effect |
| --- | --- | --- |
| Blur strength | 28 | Gaussian blur radius, adjustable from 10 to 70 |
| Start blurring | 15° | Head movement allowed before blur begins |
| Transition | 18° | Additional movement until the entire display is blurred |
| Recenter shortcut | ⌃⌥⌘C | Records the head position facing the display |

Existing saved preferences are preserved. After calibration, losing the motion signal keeps blur requested until you recenter or dismiss it. Sleep/wake and changing the active earbud require recentering.

## Rendering

ScreenCaptureKit captures display snapshots while blur is active, excluding QuietGlass itself. Core Image applies Gaussian blur without a white/gray tint or saturation change. Snapshots refresh up to four times per second and remain in memory. A directional, feathered mask animates independently at the display's reported refresh rate, using a critically damped spring to make reversals smooth. Escape, pause, and quit clear immediately.

The app does not show a solid-color cover while capture is unavailable. Before the first usable frame, the desktop stays clear and the controls show the capture error; a previously blurred frame remains visible during a transient capture failure. Screen access is necessary for the blur to work.

The floating panel stays above the blur and is clickable without replacing your current main window. The three hover buttons have black capsule backgrounds and floating labels. The right-click menu is anchored above the control row, and Recenter is disabled until tracking is ready; the settings popover opens only on demand. All app-owned icons use the free Hugeicons Stroke Rounded set; no SF Symbols are used.

## Build

Use an Apple Swift toolchain with the macOS 14 SDK or later. There are no external runtime or Swift package dependencies.

```sh
swift test
bash build.sh
```

The script creates `../QuietGlass.app` and `../QuietGlass.zip`. Pass a different app output path as its first argument if desired. Builds use the host architecture. The supplied app is for Apple silicon, locally signed, and not notarized for public distribution. A paid developer account is not required for a local build.

Signing and archiving happen in a temporary directory because Documents sync can attach Finder metadata to an unpacked app bundle. Install the verified zip's app into Applications for normal use.

## Privacy and limitations

QuietGlass captures screen images to render the effect. It does not save those images, upload data, record microphone audio, use the camera, or log motion. Only app preferences are persisted. Capture stops after the blur clears.

This is a visual blur, not a screen lock. Light blur and partial coverage can leave content readable. Head direction is not eye gaze. The desktop image updates at a lower rate than the animated mask, so video and fast-moving content beneath full blur are not reproduced at full frame rate. Multiple displays, Spaces, full-screen apps, sleep/wake, and earbud switching need broader hardware testing.

## References and icons

The initial behavior was informed by [ShyGlass](https://shyglass.app/) and [Max Rovensky's demo](https://x.com/MaxRovensky/status/2101319093592682959). This implementation is independent; the creator's private source was not available.

The compact interface is inspired by [Wispr Flow's floating bar](https://docs.wisprflow.ai/articles/1790396454-move-and-dock-the-flow-bar-on-desktop) and its [movable-bar demo](https://wisprflow.ai/whats-new). The continuous motion draws on the user's [iPhone Duo reference](https://www.apple.com/newsroom/2026/09/apple-unveils-iphone-duo/). QuietGlass uses its own blur renderer and does not reproduce Apple's optical Liquid Glass rendering.

Technical references: [headphone motion](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager), [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), and [Core Image](https://developer.apple.com/documentation/coreimage).

Icons are from [`@hugeicons/core-free-icons` 4.3.4](https://github.com/hugeicons/hugeicons), licensed under MIT. The selected SVG geometry and license are included in `Resources/Hugeicons`. `HugeIcon.swift` adapts that geometry to native SwiftUI/AppKit paths, avoiding an icon runtime dependency. The license is included in the built app.

## Source

- `Sources/ShieldCore/ShieldResponse.swift`: head pose, thresholds, feathering, and transition physics.
- `Sources/QuietGlass/ShieldOverlay.swift`: capture, Gaussian blur, display panels, and animation.
- `Sources/QuietGlass/AppModel.swift`: motion, calibration, permissions, and preferences.
- `Sources/QuietGlass/NotchBar.swift`: floating notch and compact controls.
- `Sources/QuietGlass/HugeIcon.swift`: native Hugeicons rendering.
- `Sources/QuietGlass/GlobalShortcuts.swift`: recenter and temporary Escape registration.
- `Sources/QuietGlass/QuietGlassApp.swift`: application lifecycle and menu bar.

See [VALIDATION.md](VALIDATION.md) for verified behavior and remaining hardware checks.
