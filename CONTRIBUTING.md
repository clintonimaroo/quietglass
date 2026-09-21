# Contributing to QuietGlass

Bug reports, documentation improvements, and focused pull requests are welcome. Discuss substantial features or architectural changes in an issue before starting work.

## Development setup

Use macOS 14 or later and Xcode 26 or later with its command-line tools selected. Fork the repository, clone your fork, and create a branch for your change.

```sh
swift test
bash build.sh
open ../Build.noindex/QuietGlass.app
```

The build uses the bundled recognition model and needs no API keys. AirPods and a camera are only needed when checking the features that use them. See the [README](README.md#development) for the project layout and build details.

## Making a change

- Keep changes focused and follow the existing SwiftUI, AppKit, and ShieldCore structure.
- Keep screen, camera, text, and motion processing on the Mac.
- Add regression coverage for behavior changes. Use fictional or redistributable data in fixtures and screenshots.
- Run `swift test` and `bash build.sh` before submitting code changes. For documentation-only changes, check the links and rendered formatting.

In your pull request, explain the problem, the resulting behavior, and how you verified it. For hardware-dependent changes, include the macOS version, Mac model, and relevant AirPods, camera, or display details. Distinguish automated checks from checks on real hardware.

Do not commit credentials, signing keys, build products, private screenshots, camera recordings, or biometric templates.

## Reporting issues

For ordinary bugs, include the app version, macOS version, reproduction steps, and expected and actual behavior. Remove personal information from any attached logs or screenshots.

Report vulnerabilities privately using the [Security Policy](SECURITY.md).

## License

Contributions are provided under the repository’s [MIT License](LICENSE). Contributors retain their copyright. Third-party code, models, and assets must retain their required licenses and attribution.
