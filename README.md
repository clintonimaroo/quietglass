# QuietGlass

A Mac privacy utility with AirPods head tracking, manual blur, app rules, guided calibration, Focus mode, window and area protection, local text detection, and optional nearby-person detection.

## New in this test build

- **Settings navigation:** General, Protection, App rules, and Head tracking have separate pages. Blur appearance lives in General; display calibration lives in Head tracking. The sidebar starts collapsed whenever Settings opens. Hover over the sidebar symbol to preview it, or click to keep it open. Search filters the pages by related terms. Back and Forward retrace your navigation. Command–S toggles the sidebar; hovering its button shows the shortcut. The layout uses a 275-point sidebar, centered 768-point content, compact switches, and native symbols, with Reduce Motion support.
- **Profiles:** A compact, translucent Home/Office/Public/Focus picker in Settings and the notch controls, with circular icons, pink selection feedback, and a checkmark. The notch picker stays beside the expanded controls and includes Back and Profile settings actions. Profiles also remain available in the menu bar. Home/Office/Public adjust sensitivity and blur strength; they do not start the camera or head tracking. Focus pauses head tracking and blurs outside your active window. Manual privacy blur takes priority.
- **Nearby people (experimental):** enable it in Settings to request camera access. Vision counts faces locally at up to five checks per second. A sustained second face requests blur across all displays. One face must remain for 1.5 seconds to release it; losing all faces or the camera does not release an existing blur. Escape turns the feature off. It starts off on every launch and after sleep. No photos, video, face identity, or camera history are stored or transmitted. People outside the camera view can be missed; this is not a physical privacy filter.
- **Connected displays:** full-screen blur includes external displays automatically. Optional per-display AirPods calibration stores a center for each connected display for this session. Click Center, then face that display during the three-second countdown. Once all displays are centered, the estimated nearest direction stays clear and the others blur. Before all centers are recorded, ordinary head tracking continues. Changes to the display layout or motion connection invalidate the centers. This estimates head direction, not eye gaze, and needs hardware testing.
- **Custom areas:** Choose area brings the last active app forward, hides Settings, and lets you drag inside its window. The fourth notch button and Control–Option–Command–A open the same selector. Areas follow the window position and relative size. Use Remove beside an area, Remove all areas, or Escape to discard them. Areas are session-only and clear when the source window closes.
- **Custom phrases:** add up to 50 phrases in Sensitive text. Matching is literal and ignores capitalization and accents. Only the phrases you enter are saved locally. OCR can miss words, especially across line breaks.
- **Shortcuts (pending developer signing):** Blur Screen, Pause QuietGlass, and Start Focus Mode are implemented as App Intents. macOS indexed all three during testing but rejected execution because the local test certificate has no Apple developer Team ID. These actions are omitted from this private build. The build includes their metadata when signed with an Apple developer identity; actual Shortcuts and Siri execution must then be tested.
- **Blur continuity:** transparent capture pixels retain the last rendered blur, with an opaque dark backing if no earlier image exists. Pixel tests pass, but the user confirmed that the trackpad Spaces gap still occurs in build 44, including Preview blur. It remains unresolved.

## Start

1. Build the app, or unzip `QuietGlass.zip` and move the app to Applications.
2. Connect and wear compatible AirPods, then open QuietGlass. A thin 40 × 8-point dash appears above the Dock.
3. Hover over the dash to reveal four black buttons: tracking, recenter, blur preview, and Blur an area. Hover a button to see its label.
4. Start tracking from the notch or Settings. On first use, follow the guided setup to connect AirPods, check four head directions, learn your comfortable range, and try a sample blur. Allow Motion & Fitness and Screen Recording if needed. On later launches, face the screen and click **Recenter**.
5. Look away to blur the screen; look back to clear it. **Preview blur** works without AirPods and ends after five seconds. Click **Clear preview** or press Escape to clear it sooner.

**Escape** clears the blur immediately. The default recenter shortcut is **Control–Option–Command–C**, which also starts tracking if paused. Change it under **More** in the controls.

The dash morphs into the controls on hover and smoothly closes when the pointer leaves. Its drawing area stays in place until the closing animation finishes, including when the pointer returns mid-transition. It defaults to screen center, just above the Dock, and slides down near the bottom edge in full screen or when the Dock is hidden. Returning to the desktop restores its position above the Dock. Drag it to save a custom position. The top of the display is excluded: releasing there returns the notch to its previous position, and older saved top positions return to the bottom at launch. Near either side of the screen, the notch snaps to the edge and smoothly stacks its controls vertically. Labels, compact controls, and the context menu open inward. Drag back near the bottom center to restore automatic Dock placement. **Move Notch Down** restores automatic Dock placement. Right-click for **Hide for 1 hour**, **Control**, **Settings…**, **Move Notch Down**, tracking, recenter, preview, and clear actions. Head tracking starts paused after launch and requires a new calibration. The main window opens to General with its sidebar collapsed. Open the sidebar to switch between the four Settings pages. Hover previews navigation; clicking pins it. On narrow windows the sidebar overlays the content to keep controls readable. **Control** opens the compact notch controls. **Settings…** in the notch menu, compact controls, or menu bar opens the full privacy window. Its dark layout groups related settings into bordered cards with QuietGlass pink switches. Blur strength includes a live image preview, low/high endpoint buttons, and native Liquid Glass preview controls on macOS 26 or later, with a material fallback on earlier systems. Closing the window leaves the notch running. It opens at 1112 × 850 points, fitted to the usable display area on smaller screens. The green window button and Control–Command–F toggle native full screen.

Requires macOS 14 or later. Head tracking additionally requires AirPods 3/4, AirPods Pro, or AirPods Max, with at least one compatible earbud worn. Manual protection and Nearby people work without AirPods. Permission settings are managed by macOS; a rebuilt, locally signed app may require renewed approval and a relaunch.

If Screen Recording is already on but the app still asks for access, switch **QuietGlass** off and on in **System Settings → Privacy & Security → Screen & System Audio Recording**, then choose **Restart QuietGlass** in the controls (or macOS's **Quit & Reopen**). A changed ad-hoc build has a new code identity, so an enabled row can refer to an earlier build. The app checks access again when activated and clears stale capture warnings after access is granted. Restarting opens the controls and leaves tracking paused.

If toggling and restarting still do not help, remove the stale **QuietGlass** entry from that list and add `/Applications/QuietGlass.app` again. Keep using that installed copy. Toggling an existing entry can preserve its old code requirement instead of approving the current build.

## Controls

| Control | Default | Effect |
| --- | --- | --- |
| Blur strength | 28 | Gaussian blur radius, adjustable from 10 to 70 |
| Start blurring | 15° | Head movement allowed before blur begins |
| Transition | 18° | Additional movement until the entire display is blurred |
| Recenter shortcut | ⌃⌥⌘C | Records the head position facing the display |
| Privacy shortcut | ⌃⌥⌘P | Toggles full-screen blur on every display |
| Blur an area | ⌃⌥⌘A | Opens selection in the last active app window |
| Hold to peek | ⌃⌥⌘Space | Temporarily hides privacy blur until released |

## Privacy settings

- **Instant privacy:** full-screen blur stays active until you clear it and works without AirPods. Screen Recording permission is required. Escape clears it immediately. The main window hides when privacy blur starts, and the notch remains available above it. This is visual protection, not a Mac lock.
- **App rules:** add the active app or choose an application. Each app has an inline slider with Paused, Standard, and Stronger positions. Open the rule’s ⋮ menu and choose Remove rule, or right-click the row. Standard uses your settings. Stronger caps the start angle at 8° and transition at 12° and raises blur to at least 45, without weakening settings that are already stronger. Paused applies only to automatic head blur for the frontmost app; manual, selected-window, and text protection remain independent. Rules are saved by bundle identifier.
- **Selected window:** choose a window with the macOS picker on macOS 15.2 or later, or use Protect active window on macOS 14 or later. The selected window remains blurred as it moves, accounting for windows in front. Selection lasts for this session, until removed or closed. It follows the same window identifier and does not select other windows from that app. Transient capture failure retains the last available blurred frame while you restore access or retry. Before the first captured frame, the window remains visible.
- **Guided setup:** Settings → Head tracking → Set up opens a compact motion guide with an animated head and pink progress ring. Progress comes from AirPods motion, without a camera or face scan. Complete four directions, learn a comfortable range, and check the sample blur before finishing. Automatic head blur pauses during setup. Closing the popup or pressing Escape restores your prior sensitivity and tracking state when its motion reference is still valid. After completion, the button becomes Recalibrate. Animations respect Reduce Motion.
- **Calibration:** with AirPods connected and tracking started, face your screen and choose Learn for 8 seconds. Read normally while making small movements. Head blur pauses during learning. QuietGlass uses the 95th percentile plus a 3° margin, rejects unreliable samples, and suggests an angle between 6° and 25°. Apply the suggestion explicitly. Motion loss cancels learning.
- **Local text detection:** off by default. Apple Vision recognizes visible text on your displays and blurs matching credentials, optional email addresses, and optional payment card numbers with valid checksums. Scanning is throttled to at most once per second per display; recognition can take longer, especially on first use. Text is processed in memory and never saved or uploaded. There is no LLM provider, API key, server, or external package dependency.

Escape or Clear Screen discards all selected areas and pauses window and text protection until you click Resume. Pause protection retains areas for Resume. Enabling text detection or selecting a window also resumes those features. Text-detection preferences persist across launches, while head tracking always starts paused. The first enabled scan can take time to initialize Vision. Detection can miss or misclassify text, and content may be visible before recognition finishes. Use the privacy shortcut to blur the whole display instead of waiting for text detection. Capture still needs time to produce its first frame, and lighter blur can leave text readable. Overlay protection does not guarantee redaction in recordings or screen sharing.

Existing saved preferences are preserved. After calibration, losing the motion signal keeps blur requested until you recenter or dismiss it. Sleep/wake and changing the active earbud require recentering.

Small movements around the trigger angle now stay in a tolerance band instead of restarting the effect. Clearing waits for 120 milliseconds of centered input, then fades out; returning to a turned pose interrupts that fade smoothly. The sweep edge stays consistent until the screen clears, so slight changes in head direction do not flip the blur across the display. Escape, pause, and quit still clear immediately.

## Rendering

ScreenCaptureKit streams display frames while blur is active, excluding QuietGlass itself and capturing no audio. Core Image applies Gaussian blur without a white/gray tint or saturation change. Frames update up to 30 times per second and remain in memory. A directional, feathered mask animates independently at the display's reported refresh rate, using a critically damped spring to make reversals smooth. Escape, pause, and quit clear immediately.

Automatic head blur does not show a solid-color cover while capture is unavailable. Before its first usable frame, the desktop stays clear and the controls show the capture error; a previously blurred frame remains visible during a transient capture failure. Window, text, and full-screen privacy protection all use captured Gaussian blur at your selected strength. They do not substitute black or opaque covers. Before a first frame is available, the underlying content remains visible; errors are shown in the controls.

Both blur modes use floating, nonactivating overlay panels across Spaces. Work-area notifications preserve capture sessions and the last blurred image. A physical display-frame change restarts capture only for that display, retaining its image while the replacement stream starts.

The floating panel stays above the blur and is clickable without replacing your current main window. The four hover buttons have black capsule backgrounds and floating labels. The right-click menu is a measured panel above the control row, and Recenter is disabled until tracking is ready. Escape and clicking outside close the menu; arrow keys and Return select an action. The Control popover opens only on demand, with a larger close-button target that accepts the first click. Controls use rounded stroke icons. Recenter uses a compact focus mark; Move Notch Down uses a bottom-dock symbol. The Control popover and context menu sit 8 points from the controls, including when the advanced settings resize and when the Dock hides in full screen. Clicking outside either panel closes it. The connected-AirPods indicator uses the native `airpodspro` symbol in white hierarchical rendering.

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

Known issue: blur disappears during three-finger swipes between Spaces or full-screen apps and returns after a delay. The user confirmed this in build 44 for manual, head-tracking, and Preview blur, including with Demo mode enabled. Retaining capture sessions and opaque frame compositing have not resolved it. Do not rely on this test build to hide sensitive content during Space transitions.

QuietGlass captures screen images to render blur or detect text when enabled. Optional Nearby people uses the camera, with permission, to count visible faces locally. It does not save screen or camera images, recognized text, face identity, or motion history, upload data, or record microphone audio. Only app preferences, app rules, and custom phrases are persisted. Screen capture runs while protection needs it; Nearby people also keeps capture ready while monitoring is enabled.

This is a visual blur, not a screen lock. Light blur and partial coverage can leave content readable. Head direction is not eye gaze. A live ScreenCaptureKit stream supplies up to 30 frames per second while the mask animates at the display refresh rate. Late frames are dropped instead of queued. Existing pixels and windows remain in place through Space and work-area changes and transient capture failures. This is still a composited blur, so there can be some capture latency. Multiple displays, Spaces, full-screen apps, sleep/wake, and earbud switching need broader hardware testing.

## Technical references

Technical references: [headphone motion](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager), [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), [Vision text recognition](https://developer.apple.com/documentation/vision/vnrecognizetextrequest), and [Core Image](https://developer.apple.com/documentation/coreimage).

The bundled icon geometry is rendered as native SwiftUI/AppKit paths by `AppIcon.swift`, with no runtime dependency. The required attribution is in [Resources/Icons/LICENSE.md](Resources/Icons/LICENSE.md) and packaged as `ThirdPartyNotices.txt` in the app.

## Source

- `Sources/ShieldCore/ShieldResponse.swift`: head pose, thresholds, feathering, and transition physics.
- `Sources/QuietGlass/ShieldOverlay.swift`: display panels, Space continuity, and animation.
- `Sources/QuietGlass/DisplayCapture.swift`: live display streams and bounded background Gaussian rendering.
- `Sources/ShieldCore/NotchDocking.swift`: edge docking and panel geometry.
- `Sources/QuietGlass/AppModel.swift`: motion, calibration, permissions, and preferences.
- `Sources/QuietGlass/HeadSetup.swift`: guided setup popup, live motion visualization, and sample blur check.
- `Sources/ShieldCore/HeadSetupProgress.swift`: sustained directional motion checks and invalid-sample rejection.
- `Sources/QuietGlass/NotchBar.swift`: floating notch and compact controls.
- `Sources/QuietGlass/AppIcon.swift`: native vector icon rendering.
- `Sources/QuietGlass/GlobalShortcuts.swift`: recenter, instant privacy, hold-to-peek, and temporary Escape registration.
- `Sources/QuietGlass/PrivacyController.swift`: app rules, window selection, capture, and protection lifecycle.
- `Sources/QuietGlass/PrivacySettings.swift`: privacy, app-rule, and calibration controls.
- `Sources/QuietGlass/BlurStrengthControl.swift`: live sample preview and shared blur sliders.
- `Sources/QuietGlass/LocalTextAnalyzer.swift`: bounded local Vision recognition without text persistence.
- `Sources/ShieldCore/PrivacyPolicy.swift`: app policies, calibration, and display geometry.
- `Sources/ShieldCore/SensitiveText.swift`: credential, email, and checksum-validated card detection.
- `Sources/QuietGlass/QuietGlassApp.swift`: application lifecycle and menu bar.

See [VALIDATION.md](VALIDATION.md) for verified behavior and remaining hardware checks.

## Recording a demo

Enable **Demo mode** under Full-screen privacy to allow screenshots and recordings of the entire display to include the blur. The choice persists and affects both head blur and manual privacy blur immediately. It is off on a fresh installation. Capturing an individual app window can bypass the overlay. Some macOS capture tools can include overlays even when Demo mode is off; this setting does not guarantee redaction or capture exclusion.
