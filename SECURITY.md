# Security Policy

## Reporting a vulnerability

Email **[hi@clintonimaro.com](mailto:hi@clintonimaro.com)** with the subject **QuietGlass security report**. Please report vulnerabilities privately rather than opening a public issue or pull request.

Include:

- The affected app version, macOS version, and component.
- Reproduction steps or a minimal proof of concept using fictional data.
- The expected behavior, observed behavior, and potential impact.
- Any mitigation you have identified.

Do not send passwords, signing keys, biometric templates, personal screen content, or recordings of other people. If sensitive evidence is needed, arrange how to share it before sending it.

Reports are reviewed privately. We will coordinate follow-up, a fix where appropriate, and disclosure with the reporter. Security fixes target the latest release; use the latest version when reproducing an issue where possible.

## Scope

Relevant reports include unintended screen exposure, failures in protection state or permission handling, unauthorized access to saved face data, and unexpected storage or transmission of screen or camera content.

QuietGlass controls screen visibility and complements macOS screen locking. Camera recognition is experimental, and the movement check does not provide Face ID security. See the [camera protection guide](CAMERA-PROTECTION.md) for its behavior and privacy model.
