# QuietGlass

A tiny Mac notch that blurs your screen when you look away with AirPods. It keeps the desktop's colors and softens its details, with a feathered transition that follows your head movement.

## Start

1. Build the app, or unzip `QuietGlass.zip` and move the app to Applications.
2. Connect and wear compatible AirPods, then open QuietGlass. A thin 40 × 8-point dash appears above the Dock.
3. Hover over the dash to reveal three black buttons: tracking, recenter, and blur preview. Hover a button to see its label.
4. Right-click the notch and choose **Settings…** to allow Motion & Fitness and Screen Recording if needed. Start tracking, face the screen, and click **Recenter**.
5. Look away to blur the screen; look back to clear it. **Preview blur** works without AirPods and ends after five seconds. Click **Clear preview** or press Escape to clear it sooner.

**Escape** clears the blur immediately. The default recenter shortcut is **Control–Option–Command–C**, which also starts tracking if paused. Change it under **More** in the controls.

The dash morphs into the controls on hover and smoothly closes when the pointer leaves. Its drawing area stays in place until the closing animation finishes, including when the pointer returns mid-transition. It defaults to screen center, just above the Dock, and slides down near the bottom edge in full screen or when the Dock is hidden. Returning to the desktop restores its position above the Dock. Drag it to save a custom position. The top of the display is excluded: releasing there returns the notch to its previous position, and older saved top positions return to the bottom at launch. Near either side of the screen, the notch snaps to the edge and smoothly stacks its controls vertically. Labels, settings, and the context menu open inward. Drag back near the bottom center to restore automatic Dock placement. **Move Notch Down** restores automatic Dock placement. Right-click for **Hide for 1 hour**, **Settings…**, **Move Notch Down**, tracking, recenter, preview, and clear actions. The menu bar eye offers show/hide, position reset, controls, and quit. The app starts paused after launch and requires a new calibration. There is no main settings window.

Requires macOS 14 or later and AirPods 3/4, AirPods Pro, or AirPods Max. At least one compatible earbud must be worn. Permission settings are managed by macOS; a rebuilt, locally signed app may require renewed approval and a relaunch.

If Screen Recording is already on but the app still asks for access, switch **QuietGlass** off and on in **System Settings → Privacy & Security → Screen & System Audio Recording**, then choose **Restart QuietGlass** in the controls (or macOS's **Quit & Reopen**). A changed ad-hoc build has a new code identity, so an enabled row can refer to an earlier build. The app checks access again when activated and clears stale capture warnings after access is granted. Restarting opens the controls and leaves tracking paused.

If toggling and restarting still do not help, remove the stale **QuietGlass** entry from that list and add `/Applications/QuietGlass.app` again. Keep using that installed copy. Toggling an existing entry can preserve its old code requirement instead of approving the current build.

## Controls

| Control | Default | Effect |
| --- | --- | --- |
| Blur strength | 28 | Gaussian blur radius, adjustable from 10 to 70 |
| Start blurring | 15° | Head movement allowed before blur begins |
| Transition | 18° | Additional movement until the entire display is blurred |
| Recenter shortcut | ⌃⌥⌘C | Records the head position facing the display |

Existing saved preferences are preserved. After calibration, losing the motion signal keeps blur requested until you recenter or dismiss it. Sleep/wake and changing the active earbud require recentering.

Small movements around the trigger angle now stay in a tolerance band instead of restarting the effect. Clearing waits for 120 milliseconds of centered input, then fades out; returning to a turned pose interrupts that fade smoothly. The sweep edge stays consistent until the screen clears, so slight changes in head direction do not flip the blur across the display. Escape, pause, and quit still clear immediately.

## Rendering

ScreenCaptureKit streams display frames while blur is active, excluding QuietGlass itself and capturing no audio. Core Image applies Gaussian blur without a white/gray tint or saturation change. Frames update up to 30 times per second and remain in memory. A directional, feathered mask animates independently at the display's reported refresh rate, using a critically damped spring to make reversals smooth. Escape, pause, and quit clear immediately.

The app does not show a solid-color cover while capture is unavailable. Before the first usable frame, the desktop stays clear and the controls show the capture error; a previously blurred frame remains visible during a transient capture failure. Screen access is necessary for the blur to work.

The floating panel stays above the blur and is clickable without replacing your current main window. The three hover buttons have black capsule backgrounds and floating labels. The right-click menu is a measured panel above the control row, and Recenter is disabled until tracking is ready. Escape and clicking outside close the menu; arrow keys and Return select an action. The settings popover opens only on demand, with a larger close-button target that accepts the first click. Controls use rounded stroke icons. Recenter uses a compact focus mark; Move Notch Down uses a bottom-dock symbol. Settings and the context menu sit 8 points from the controls, including when the advanced settings resize and when the Dock hides in full screen. Clicking outside either panel closes it. The connected-AirPods indicator uses the native `airpodspro` symbol in white hierarchical rendering.

## Build

Use Xcode 26 or later with its command-line tools selected. The app supports macOS 14 or later. There are no external runtime or Swift package dependencies.

```sh
swift test
bash build.sh
```

The script creates `../Build.noindex/QuietGlass.app` and `../QuietGlass.zip`. The intermediate bundle stays out of Spotlight so it does not compete with the installed copy. Install the app from the zip into Applications. Pass a different app output path as the first argument to place both the app and zip beside that path. Builds use the host architecture. The supplied app is for Apple silicon, locally signed, and not notarized for public distribution. A paid developer account is not required for a local build.

The editable app icon is `Resources/AppIcon/QuietGlass.icon`. Open it in Icon Composer to edit the vector eyelash and its appearances. Both light and dark appearances have a pink background and black eyelash, using the shortcut label's sRGB pink (0.94, 0.68, 0.91). Liquid Glass applies to the background; the eyelash stays flat. The build compiles the layered icon into `Assets.car` and includes an `.icns` fallback for older macOS versions.

The build reuses the installed **QuietGlass Local Development** identity, or an Apple Development identity when available. You can explicitly select an identity:

```sh
QUIETGLASS_SIGN_IDENTITY="Apple Development: Your Name (IDENTIFIER)" bash build.sh
```

Use the actual identity reported by `security find-identity -v -p codesigning`. If that identity is unavailable, signing fails rather than silently changing identities. This setting does not create a certificate or grant Screen Recording. Without an installed identity, a build falls back to ad-hoc signing and prints a warning. To create a stable identity for local use, explicitly run `bash scripts/setup-local-signing.sh` once. It stores a private key in your login Keychain and adds user-level trust limited to code signing. It does not change TLS trust or grant screen access. Keep that identity for future builds; replacing it requires renewed approval. This local identity is not for notarized public distribution. Apple explains why [ad-hoc rebuilds lose capture permission](https://developer.apple.com/forums/thread/819406).

Signing and archiving happen in a temporary directory because Documents sync can attach Finder metadata to an unpacked app bundle. Install the verified zip's app into Applications for normal use.

## Privacy and limitations

QuietGlass captures screen images to render the effect. It does not save those images, upload data, record microphone audio, use the camera, or log motion. Only app preferences are persisted. Capture stops after the blur clears.

This is a visual blur, not a screen lock. Light blur and partial coverage can leave content readable. Head direction is not eye gaze. A live ScreenCaptureKit stream supplies up to 30 frames per second while the mask animates at the display refresh rate. Late frames are dropped instead of queued. Existing pixels and windows remain in place through Space and work-area changes and transient capture failures. This is still a composited blur, so there can be some capture latency. Multiple displays, Spaces, full-screen apps, sleep/wake, and earbud switching need broader hardware testing.

## Technical references

Technical references: [headphone motion](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager), [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), and [Core Image](https://developer.apple.com/documentation/coreimage).

The bundled icon geometry is rendered as native SwiftUI/AppKit paths by `AppIcon.swift`, with no runtime dependency. The required attribution is in [Resources/Icons/LICENSE.md](Resources/Icons/LICENSE.md) and packaged as `ThirdPartyNotices.txt` in the app.

## Source

- `Sources/ShieldCore/ShieldResponse.swift`: head pose, thresholds, feathering, and transition physics.
- `Sources/QuietGlass/ShieldOverlay.swift`: display panels, Space continuity, and animation.
- `Sources/QuietGlass/DisplayCapture.swift`: live display streams and bounded background Gaussian rendering.
- `Sources/ShieldCore/NotchDocking.swift`: edge docking and panel geometry.
- `Sources/QuietGlass/AppModel.swift`: motion, calibration, permissions, and preferences.
- `Sources/QuietGlass/NotchBar.swift`: floating notch and compact controls.
- `Sources/QuietGlass/AppIcon.swift`: native vector icon rendering.
- `Sources/QuietGlass/GlobalShortcuts.swift`: recenter and temporary Escape registration.
- `Sources/QuietGlass/QuietGlassApp.swift`: application lifecycle and menu bar.

See [VALIDATION.md](VALIDATION.md) for verified behavior and remaining hardware checks.
