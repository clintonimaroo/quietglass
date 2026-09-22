# Camera protection

**Nearby people** detects additional faces in the camera’s view and either warns you beside the notch or blurs your displays. AirPods are not required. Optional **Recognize me** checks your saved face before clearing that response.

## Setup

1. Open **Settings → Protection → Nearby people** and enable **Detect additional faces**. Allow camera access when prompted.
2. Choose **Warn me** for a warning before blur, or **Blur automatically** to cover the screen as soon as detection is confirmed. Warn me defaults to 2 minutes. Click the pencil beside **Blur after**, enter hours and minutes, and click the checkmark to save a delay from 1 minute to 24 hours.
3. To add owner recognition, choose **Set up my face → Get started** and authenticate with Touch ID or your Mac password. Sit alone in good light, look at the camera, turn your head slightly as prompted, then look back. You can blink naturally; there is no close-eyes step.
4. Choose **Save my face**, then enable detection again. Authenticate to load your saved face and follow the short verification prompts beside the notch.

Use **Set up again** to replace your template, or click the trash button and confirm with the pink checkmark to remove it. Both require authentication. Changing Recognize me stops monitoring; enable detection again to use the new setting.

## Check your camera coverage

Choose **Automatic** or a specific camera, then click **Run check**. Click **Start camera**, stay centered, and ask someone to enter from each side of the preview. A green check means a face was observed in that part of the image; it is not a guarantee of coverage beyond the image. If a selected camera is disconnected, reconnect it or choose another camera. QuietGlass does not silently change a specifically selected camera.

**Try warning** demonstrates a three-second warning followed by three seconds of blur. **Try blur** demonstrates immediate blur for three seconds. These tests leave your normal delay unchanged. Nearby monitoring pauses during the check and resumes when you finish; camera frames are never saved. Escape stops the demonstration and monitoring.

## How it behaves

- Detection and response preferences are remembered across launches. Monitoring pauses during sleep or an inactive login session and resumes when you return. Owner recognition requires authentication for each new monitoring session.
- Without Recognize me, a steady single face clears the response; it does not have to be your face. With Recognize me, clearing requires a matching face, a small head turn in the prompted direction, and a look back at the camera.
- **Warn me** shows a countdown, then blurs if the warning is still unresolved. Clearing the warning cancels its timer; Escape stops monitoring. Hovering over the notch, opening Settings, or changing verification prompts does not restart the timer. A camera failure also starts a countdown. Once blur starts, extending the delay does not clear it; the warning must resolve or monitoring must be stopped. **Blur automatically** skips the warning delay.
- Click the notch warning to open **Nearby people** settings. Use **Blur now** there to cover immediately. **Pause 5 min** stops the camera and clears the camera response, with a visible resume countdown. **Resume** restarts it early. The pause survives relaunch, and a deadline reached while your Mac is asleep waits until the session is active again. Turning detection off or pressing Escape cancels automatic resume.
- After successful owner verification, a brief landmark loss on the continuously visible face can recover without another head turn. Protection still covers after sustained uncertainty and clears only after fresh, steady matching samples. A different face, loss of the face, a stale sample gap, or an expired recovery window requires the complete movement check again. Matching thresholds are unchanged.
- Notices distinguish another face, no visible face, an unreadable face, and an unmatched face. Brief camera fluctuations do not replace the current instruction; this filtering affects the text, not the protection decision.
- Brief changes are filtered to reduce flickering. A missing face or camera failure does not clear an active response; use the status and recovery controls in Settings.
- A short sound plays once when a warning first appears beside the notch. Hovering over controls or changing verification prompts does not repeat it. Turn off **Play warning sound** in Nearby people for silent alerts; this choice is remembered.
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

Detection is limited to visible faces, and lighting, glasses, or occlusion can affect it. Recognition and the movement check can be fooled by photos or video. They complement macOS screen locking; they do not provide Face ID security or make a clear screen visible only to its owner.
