# Validation — September 19, 2026

## Build 9 checks

- All 14 automated response tests passed with no failures.
- The release build, build script syntax check, plist validation, and whitespace checks passed.
- The packaged application passed strict signature verification. Hardware verification limits remain documented below.

## Repository wording cleanup (build 9)

- Reworded the two older commit titles with plain feature descriptions. Verified that all three rewritten commits retain their original file trees, authors, and dates.
- Renamed the icon renderer to AppIcon/AppIconView and moved its assets to Resources/Icons. Removed design-reference and vendor wording from the current source comments, documentation, filenames, and build script. The required copyright and permission notice remains intact and is packaged as ThirdPartyNotices.txt.
- Compared all nine source/test files with the pre-cleanup snapshot after normalizing the identifier changes; no behavior changed. All icon geometry and the license notice are byte-for-byte identical.
- A clean release build, shell syntax check, plist validation, and git diff --check passed. The archived build passed strict signature verification. The application and source archives were refreshed; the existing running application was left in place for this naming-only change.

## Persistent preview and Dock placement update (build 8)

- Removed the five-second preview task. Preview stays active until explicitly cleared; the notch button, hover hint, context menu, controls, and menu bar show Clear preview while it is active. Escape, pause, recenter, sleep, and permission revocation retain their existing clear behavior.
- In the running app, the context menu still showed Clear preview more than five seconds after it was first observed active. Clicking it cleared the preview, and reopening the menu showed Preview blur again.
- Automatic placement now checks the on-screen Dock window geometry, ignoring the hidden activation strip and side Docks. This avoids the stale desktop inset reported by AppKit in another app's full-screen Space. Space/app changes and a 0.5-second geometry refresh update the position, with a 0.28-second animation and Reduce Motion support. Dragged custom positions remain fixed; open controls and active drags defer repositioning.
- The corrected installed build recorded the bottom-edge anchor at y = 20 instead of the previous y = 118. Chrome's native View menu confirmed a full-screen window during the check. The complete return above the visible Dock is awaiting direct confirmation; multi-display behavior needs broader testing.
- All 14 existing response tests passed. The release build, plist validation, strict signature verification of the installed Applications bundle, and git diff --check passed. Screen Recording was refreshed for the changed ad-hoc build; the setup warning disappeared, and the running controls again showed connected AirPods.

## AirPods icon update (build 7)

- Replaced the connected-AirPods indicator with Apple's native `airpodspro` symbol, using white hierarchical rendering at 18 points. The remaining controls keep their rounded stroke icons.
- Rendered the installed macOS symbols locally to inspect the AirPods Pro shape and hierarchical shading. The screenshot's blue desktop background is not part of the app asset.
- Release build and `git diff --check` passed. The installed Applications bundle passed strict signature verification. Screen access was refreshed, the setup warning disappeared, and the running app subsequently presented its blur overlay.
- This cosmetic change does not modify motion or blur behavior; the existing 14-test result applies to the unchanged response logic. No additional tests were added for the icon swap.

## Transition update (build 6)

- The user confirmed motion tracking works, but the blur pops in/out and flickers while looking away. Bluetooth inspection confirmed AirPods Pro connected, and Core Motion logs showed the headphone reference attitude initialized. No motion-permission reset was needed.
- Added up to 3 degrees of entry/exit tolerance so small movements around the trigger do not repeatedly stop and restart capture. A 120 ms clear delay ignores brief centered samples; renewed coverage cancels the delay. Escape and explicit clear cancel it immediately.
- Reduced spring frequency from 28 to 16 for a more visible fade, preserving continuous velocity on reversal. Locked the sweep direction until clearing so switching the dominant head axis cannot instantly flip the mask.
- Added regression coverage for trigger jitter, recenter/Escape state reset, low-angle clearing/rearming, and visible fade duration. All 14 tests passed; the final combined release build compiled without warnings.
- Replaced the clipped native notch context menu with a measured 252-point panel anchored above the controls. The full six-action menu was visually inspected, Settings opened the controls, Recenter was disabled while paused, and Escape closed the menu in live UI checks. Arrow-key/Return handling and outside-click dismissal are implemented.
- Replaced the tiny close icon's hit area with a 28-point native button that accepts the first mouse click while inactive, using the same vector asset. A single click on Close controls removed the live popover. The close action now calls the popover's direct close method.
- The combined app was installed in Applications and passed strict signature verification. Screen Recording was refreshed for its changed ad-hoc identity and the app relaunched. Its setup warning disappeared. Starting tracking produced live AirPods samples and enabled Recenter; the controls were left open for the user to face the screen and recalibrate.
- The final feel and flicker behavior need a direct head-turn check on the user's Mac.

## Permission recovery update (build 5)

- Reproduced the mismatch: System Settings showed QuietGlass's Screen Recording switch on, while the unchanged app still reported access unavailable after a full restart.
- Confirmed the build uses an ad-hoc designated requirement tied to its code hash. No valid code-signing identities are installed on this Mac. Apple's Developer Technical Support confirms that changed ad-hoc builds are treated as new apps for capture permission.
- The protected TCC database was not readable, but focused macOS TCC logs confirmed that toggling the old Screen Recording entry retained code requirement `987e4e539a833cc62097952ff8662d0d71e2c1b1`, while build 5 is `6ba425364ea5ba74d3e705e4da416934d6f6f219`. The permission UI's enabled state did not authorize the running build.
- Installed the clean archive into `/Applications/QuietGlass.app`, verified its strict signature, and launched that copy. Finder metadata on the Documents copy causes strict verification to fail; ordinary signature verification still passes. This packaging issue alone was not established as the cause of the TCC denial.
- Added a recovery explanation, Screen Settings and Restart QuietGlass actions, permission refresh on app activation, and clearing of stale capture notices after permission changes. No grant is inferred from the recovery action; the app still checks macOS.
- Verified the new recovery controls through accessibility. Restart QuietGlass relaunched the same output bundle, leaving one app process running and preserving the user's saved sensitivity.
- `swift test`: 10 tests passed. Release build 5, `bash -n build.sh`, plist validation, and `git diff --check` passed.
- `QUIETGLASS_SIGN_IDENTITY` now accepts an installed signing identity; the default remains ad-hoc and prints a permission warning. It does not create a certificate or grant access.
- After toggling proved insufficient, reset only `ScreenCapture` for `local.clinton.QuietGlass` with `tccutil` and requested access from the installed app. After the user's Touch ID approval, TCC logs showed the correct build-5 requirement allowed. macOS's Quit & Reopen relaunched the installed copy, and its live action changed from Set up screen blur to Start tracking.
- The installed app's preview created its full-display `QuietGlass Blur` panel. That panel is shown only after capture and Gaussian rendering produce an image, confirming the pipeline reached a usable frame. The panel cleared afterward. The UI capture tool returned a blank image for this non-shareable overlay and occasionally failed during window transitions, so it did not establish the final visual appearance or a precise Escape dismissal latency.

## Passed

- `swift test`: 10 tests, 0 failures. Covers thresholds, Escape suppression/rearming, recenter, ±180° wraparound, head nod versus sideways tilt, invalid angle input, directional mask feathering, full/zero coverage, frame-rate-independent spring motion, and smooth reversal/reset.
- Release build 4 compiled without warnings on this Apple silicon Mac; all 10 tests passed again after the hover/placement fix.
- `Info.plist` validation passed; includes the Motion usage description and macOS 14 minimum.
- The rebuilt app launched as a 40 × 8-point resting dash inside a 44 × 12-point panel, without the former full settings window. The resting state and expanded 116 × 30-point row of three black icon buttons were visually inspected.
- Right-clicking both the resting dash and expanded controls opened the native context menu. Settings opened the controls popover. Its accessibility tree exposed Start/Pause, Recenter, the screen permission action, both primary sliders, More, and Preview blur. Previously saved movement sensitivity was retained.
- Default placement migrated from the old saved position to x = 756, y = 118 points on this 1512-point-wide display. Custom-position mode remained off during verification.
- Recenter was confirmed disabled in the live right-click menu while tracking was paused. Menu positioning now uses an explicit point above the full control row instead of the click location.
- The persistent animation canvas showed both resting and expanded states and returned to the resting dash. Closing waits for animation completion before shrinking the native panel, with a generation guard for rapid reentry.
- More expanded to expose the transition slider and custom recenter shortcut. The notch was observed returning to its collapsed state after pointer interaction ended.
- All app-owned icons were replaced with the bundled MIT-licensed vector geometry. No `systemName`, `systemImage`, or `systemSymbolName` calls remain in the source. The notice is packaged with the app.
- The final app zip was extracted to a temporary directory and passed `codesign --verify --strict --verbose=2`. The required icon license notice was present in the extracted app.
- Earlier live checks in this development session observed AirPods motion, calibration, head-triggered coverage, and Escape dismissal. These were performed before the final notch/icon rebuild.

## Remaining verification

- **Final display blur appearance:** build 5 now has Screen Recording access and successfully presents a rendered preview. The capture tool could not visually inspect the non-shareable overlay, so its final appearance still needs a direct user check. The current app keeps the screen clear and opens setup when access is unavailable; it does not substitute a white/gray cover.
- The final notch's drag/persistent-position behavior, one-hour snooze expiry, full keyboard navigation, and popover/tooltip layout across display configurations need broader interaction testing. The floating label and right-click menu use separate native windows that the UI capture tool could not include in the notch screenshot; menu entries and actions were verified through accessibility.
- Multiple displays, full-screen apps/Spaces, actual sleep/wake, and swapping the active earbud were implemented but not exhaustively exercised on hardware.

## Packaging

`build.sh` verifies the locally signed bundle before archiving. Signing and archiving happen in a temporary directory because Documents sync can add Finder metadata to unpacked bundles. Use the supplied zip for installation into Applications.

The app starts paused after relaunch. macOS manages Motion & Fitness and Screen Recording approvals; they are not granted automatically.
