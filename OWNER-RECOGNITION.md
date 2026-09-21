# Optional owner recognition

**Experimental, build 64.** Recognize me adds face matching to Nearby people so a different single face cannot clear protection just by replacing you. It is a convenience privacy feature, not Face ID or a Mac lock. Face matching can make mistakes; a photo, video, mask, virtual camera or deepfake may fool it. Use macOS Lock Screen for security when leaving your Mac.

## Setup

1. Open **Settings → Protection → Nearby people → Set up my face**. Monitoring stops while you set up.
2. Choose **Get started** and authenticate with Touch ID or your Mac password. Allow camera access if asked.
3. Your live camera view appears inside a circular guide. Sit alone in good light with your eyes open. Follow the prompts to turn slightly, face the camera, close both eyes briefly, and reopen them.
4. Choose **Save my face**. The camera stops after collection; Cancel discards the unsaved template.
5. Enable **Nearby people**. Authenticate to use the saved template for this session. In automatic-blur mode, protection starts covered. Follow the short movement/eye check beside the notch to clear it.

Recognition stays optional. **Warn me** shows the same check and warnings without blurring. Changing Recognize me stops monitoring; enable Nearby people again to start a fresh session. Escape deliberately stops all monitoring and clears protection.

**Set up again** replaces your face only after a successful save. **Delete… → Delete face data** requires authentication and removes the Keychain item. A failed replacement leaves the previous item intact. Monitoring starts off on launch, after sleep, and after the login session becomes inactive.

## What stays on your Mac

The mirrored enrollment preview uses the same camera session as recognition and disappears on completion, cancellation or failure. It is not a depth scan. Camera frames and aligned crops exist only during processing; no photos, video, names or face data are uploaded or logged. Enrollment saves five normalized 128-number face embeddings, an eye-openness calibration and a model version. This is biometric data, even though it is not a photo. Keep access to your Mac account secure.

The locally signed build uses the encrypted macOS login Keychain, with an explicit access list trusting the signed QuietGlass app. Touch ID/password checks are enforced by the app before setup, retrieval each session, and deletion. Templates in memory are discarded on stop/sleep. The Keychain item is not marked for iCloud synchronization, but the login keychain may be part of a Mac backup. This is **not** Secure Enclave or hardware-bound biometric storage. Apple's Data Protection Keychain requires provisioned signing entitlements this local build does not have; there is no plaintext fallback. See [Apple’s keychain implementation note](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains).

## Model and protection behavior

- [OpenCV Zoo SFace](https://github.com/opencv/opencv_zoo/tree/47534e27c9851bb1128ccc0102f1145e27f23f98/models/face_recognition_sface), Apache-2.0, runs locally through Core ML. Vision supplies face detection and landmarks; it does not establish identity itself.
- Five landmarks align a 112×112 RGB crop. Full-precision CPU inference produces an embedding. The median similarity to saved samples must be at least 0.50 and every sample at least 0.35. These are experimental thresholds, not calibrated confidence percentages. There is no automatic template adaptation from unverified faces.
- Exactly one matching face must complete the prompted sequence. Extra faces, absent landmarks, an unrecognized face, and poor-quality crops cannot advance it. Each fresh blur event chooses a new left/right prompt.
- Recognition starts protected. Repeated mismatches cover after 0.35 seconds; capture gaps reset verification. Camera/model/template errors retain or request protection and require recovery. They never fall back to count-only clearing. Stopping protection is always an explicit override.
- Owner analysis is limited to about 10 frames/second; count-only mode stays at 5. The camera frame-rate cap applies only when supported. End-to-end latency, CPU and battery impact have not been measured.

The movement/eye sequence is an obstacle to a static photo, **not a validated liveness detector**. A recording or injected camera stream may reproduce it. The app cannot protect against someone outside the camera’s view or prevent other viewers seeing the screen while it is clear.

## Verification and pending tests

Automated tests cover owner replacement using supplied embeddings, multiple/no faces, failed authentication, corrupt/missing templates, stale frames, camera loss/retry, warning mode, setup cancellation, save/delete behavior, still-pose and out-of-order challenge sequences. An isolated temporary Keychain test exercises the actual storage API without touching the user’s saved face. Native model tests verify inference, normalization, RGB channel order, top-left crop orientation and landmark alignment. These tests do **not** measure real-face accuracy or prove spoof resistance.

The [conversion report](Resources/Models/conversion.json) compares Core ML against the pinned ONNX model on four synthetic inputs. Cosine agreement exceeds 0.99999. Reproduce it on macOS with an isolated Python environment:

```sh
python3 -m venv .model-venv
.model-venv/bin/pip install -r scripts/model/requirements.txt
.model-venv/bin/python scripts/model/convert-sface.py \
  --onnx /tmp/quietglass-sface.onnx \
  --output Sources/QuietGlass/Resources/SFace.mlmodel \
  --report Resources/Models/conversion.json
```

Normal builds use the bundled model and need no Python packages or model download. The conversion script checks the original weights' SHA-256 before conversion. The compiled model and attribution are included in the signed app bundle.

Before relying on this feature, complete these pending checks with consenting participants:

| Check | Record |
| --- | --- |
| Owner enrollment and return | Confirm prompt direction, eyes-open baseline, matching with glasses, pose and light changes; false rejects and time to clear |
| Different person replaces owner | No unintended clearing; false accept rate across multiple participants and repeated trials |
| Multiple people, owner absent | Repeated additional/missing faces retain protection |
| Photo on paper/phone, video replay | Whether each attack passes; count every acceptance as a failure |
| Moving photo, prerecorded challenge, virtual camera | Whether the challenge can be replayed or injected; no claim of defense until tested |
| Locked Keychain, cancelled Touch ID/password, camera permission/retry | Clear recovery, no new enrollment or unintended release |
| Sleep, display sleep, session switch, Escape | Camera stops; enrollment/cache discarded; saved preference retained |
| CPU/battery and external cameras | Measure realistic sessions and compare count-only/owner modes |

The user deferred the real two-person check. No live enrollment, identity comparison, photo/video spoof test or battery measurement has been marked as passed.
