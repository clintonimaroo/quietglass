# QuietGlass

A macOS privacy app that blurs your screen when you look away, with manual protection for screens, windows, and selected areas.

## Features

- AirPods head tracking with guided calibration.
- Instant screen blur, window protection, and custom blur areas.
- Focus mode to keep your active window clear.
- Home, Office, Public, and Focus profiles, plus per-app rules.
- Local detection of sensitive text and custom phrases.
- Experimental camera detection of nearby people, with a warning or automatic blur.

## Setup

Requires **macOS 14+**. Compatible AirPods are needed only for head tracking.

To build from source, install **Xcode 26+** and select its command-line tools in Xcode settings. No API keys or third-party packages are required.

```sh
git clone https://github.com/clintonimaroo/quietglass.git
cd quietglass
swift test
bash build.sh
```

The build creates `../QuietGlass.zip` and `../Build.noindex/QuietGlass.app` for your Mac's architecture. Unzip the archive, move QuietGlass to Applications, and open it. Local builds are not notarized.

On first use:

1. Allow **Screen Recording** when prompted to enable blur.
2. For head tracking, wear your AirPods, choose **Start tracking**, and complete setup. Allow **Motion & Fitness** when prompted.
3. Optionally enable **Nearby people** and allow **Camera** access. Manual blur works without AirPods or the camera.

Hover over the small bar above the Dock to open the controls. Settings opens with its sidebar collapsed.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌃⌥⌘P | Toggle screen blur |
| ⌃⌥⌘A | Select a blur area |
| ⌃⌥⌘C | Recenter or start head tracking |
| ⌃⌥⌘Space | Hold to peek through manual screen blur |
| Escape | Clear protection and stop camera monitoring |
| ⌘S | Toggle the settings sidebar |

## Privacy

All screen, text, camera, and motion processing happens on your Mac.

- Captured images, recognized text, and motion history are not saved or uploaded.
- Only preferences, app rules, and custom phrases are stored locally.
- Camera access is optional and used only while **Nearby people** is enabled. It starts off on launch and after sleep.
- QuietGlass does not record microphone audio.

## Testing and limitations

This is an experimental build. Blur can disappear during Spaces transitions; it is not a screen lock or guaranteed recording redaction. Nearby people counts visible faces, does not recognize the owner, and still needs testing with a second person.

See [validation notes](VALIDATION.md) and the [camera test plan](NEARBY-PEOPLE-TESTING.md).

## License

A project license has not been selected. Third-party icon attribution is in [Resources/Icons/LICENSE.md](Resources/Icons/LICENSE.md).
