# Camera protection

**Nearby people** detects additional faces in the camera’s view and either warns you beside the notch or blurs your displays. AirPods are not required. Optional **Recognize me** checks your saved face before clearing that response.

## Setup

1. Open **Settings → Protection → Nearby people** and enable **Detect additional faces**. Allow camera access when prompted.
2. Choose **Warn me** to keep your screen clear with an alert, or **Blur automatically** to cover it when another face is detected.
3. To add owner recognition, choose **Set up my face → Get started** and authenticate with Touch ID or your Mac password. Sit alone in good light and follow the turn, face-forward, and eye-close prompts in the circular camera guide.
4. Choose **Save my face**, then enable detection again. Authenticate to load your saved face and follow the short verification prompts beside the notch.

Use **Set up again** to replace your template or **Delete… → Delete face data** to remove it. Both require authentication. Changing Recognize me stops monitoring; enable detection again to use the new setting.

## How it behaves

- Detection and response preferences are remembered across launches. Monitoring pauses during sleep or an inactive login session and resumes when you return. Owner recognition requires authentication for each new monitoring session.
- Without Recognize me, a steady single face clears the response; it does not have to be your face. With Recognize me, clearing requires a matching face and the prompted movement and eye check.
- Brief changes are filtered to reduce flickering. A missing face or camera failure does not clear an active response; use the status and recovery controls in Settings.
- **Escape** clears protection and turns monitoring off until you enable it again.

## Privacy

Camera processing stays on your Mac. Frames and face crops are not saved or uploaded. Enrollment stores a biometric template, eye calibration, and model version in the encrypted macOS login Keychain. QuietGlass requires Touch ID or your Mac password before enrollment, loading the template, or deletion, and discards its in-memory template when monitoring stops.

The saved template is not a photo. It uses the login Keychain rather than Secure Enclave storage and may be included in a Mac backup.

## Implementation

AVFoundation supplies camera frames, Vision detects faces and landmarks, and the bundled SFace model performs local matching through Core ML. Normal builds need no API keys or model downloads.

- [Camera controller](Sources/QuietGlass/NearbyPeople.swift): capture, status, interruptions, and recovery.
- [Recognition policy](Sources/ShieldCore/OwnerRecognitionPolicy.swift): matching, enrollment, and verification steps.
- [Template storage](Sources/QuietGlass/OwnerTemplateStore.swift): authentication and Keychain access.
- [Model conversion](scripts/model/convert-sface.py) and [SFace license](Resources/Models/SFace-LICENSE.txt): model maintenance and attribution.

Detection is limited to visible faces, and lighting, glasses, or occlusion can affect it. Recognition and the movement check are experimental and can be fooled by photos or video. They complement macOS screen locking; they do not provide Face ID security or make a clear screen visible only to its owner.
