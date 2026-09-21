# Nearby people test plan

Build 61 adds warning and automatic-blur responses. Build 62 changes only the preview image and its presentation. It remains experimental. Face detection cannot identify the owner or establish that someone is reading the screen. A normal display blurs for everyone when automatic blur is active.

## Automated checks

All 75 package tests pass. The camera controller uses an injected camera, permission result, and monotonic clock for deterministic tests without camera access or image fixtures.

| Scenario | Test type | Required outcome | Result |
| --- | --- | --- | --- |
| Warning response | Controller | Sustained second face shows attention; no blur or screen-capture warmup | Passed |
| Passing face and unstable counts | State/controller | Brief extra faces do not trigger; a stable detection requests blur once | Passed |
| Additional face leaves | State/controller | Stable one-face readings for 1.5 seconds release the response | Passed |
| No faces, missing/stale frames | State/controller | No existing blur is released; stale frames cannot keep a dead camera healthy | Passed |
| Camera disconnect/interruption | Controller | Stop the worker, show recovery, preserve existing blur | Passed |
| Retry while blurred | Controller | Restart with fresh timing; old callbacks cannot release or change the new session | Passed |
| Warning/blur mode changes | Controller | Update only Nearby people's coverage and capture requirement | Passed |
| Camera permission denied | Controller | No worker/capture starts; show Camera Settings and Retry | Passed |
| Stop during permission request | Controller | A late permission result cannot reopen the camera | Passed |
| Stop then re-enable | Controller | Ignore late callbacks; begin without the old alert | Passed |
| Launch preferences | Controller | Remember response, start monitoring off | Passed |
| Escape registration fails | Privacy integration | Report unavailable protection, never ready | Passed |
| Notch positioning | Existing geometry tests | Keep attached popup within display bounds for supported edges | Passed |

Coverage target: every protection transition, cancellation, failure, and recovery above must have a regression test. Unit results validate the response to supplied face counts, not real-world recognition accuracy.

## Live checks

The installed app must be checked separately for the response selector, renamed recording toggle, startup with camera permission, warning placement, Escape, retry, and screen-capture status. Record exactly which checks ran in VALIDATION.md. No camera images or video should be saved for these checks.

## Human and hardware checks still required

The user deferred the two-person check. These remain pending and are not release-quality accuracy or battery claims.

| Scenario | Procedure | Measure |
| --- | --- | --- |
| Two people | Start alone, add a second person at several visible positions, then have them leave | True detections, misses, false alerts; time to warning/visible blur and clear |
| Passerby | Walk behind and beside the seated user at different speeds | Short detections ignored, sustained detections surfaced; nuisance alerts |
| Low light/backlight | Repeat at room light, dim light, and with a bright window behind | Misses and false alerts; no-face status and retained protection |
| Glasses/pose | Repeat with glasses, reflections, hats, partial occlusion, and side-facing people | Recognition limits without implying identity or gaze detection |
| Camera view limits | Position someone outside the camera view while they can still see the screen | Document the blind spot; do not claim protection there |
| Owner replacement/photo | Owner leaves while another face remains; show a face photograph | Document count-only limitations; do not treat this as owner authentication |
| Camera contention/loss | Use another camera app, disconnect an external camera, cover lens, then retry | Useful status, recovery, and no unintended release of existing blur |
| Escape, sleep, relaunch | Trigger the response, then stop or sleep/reopen | Camera releases; monitoring starts off; response choice persists |
| Battery/CPU | Compare off, Warn me, and automatic blur under the same workload, brightness, camera, and power conditions | CPU time, memory, battery drain and session length; repeat on battery |

The detector currently waits 0.35 seconds of repeated extra-face observations and 1.5 seconds of repeated single-face observations. These are state thresholds, not measured camera-to-display latency. Startup, image processing, sample intervals, screen capture, and rendering add delay. Analysis runs at most five times per second; the camera rate is capped at five frames per second only when its active format supports that rate and automatic frame rate is disabled. Automatic blur keeps display capture ready, which adds work compared with warning mode.

## Implementation references

Apple's [face rectangle detector](https://developer.apple.com/documentation/vision/vndetectfacerectanglesrequest) supplies face observations. [Capture runtime errors](https://developer.apple.com/documentation/avfoundation/avcapturesession/runtimeerrornotification) and interruption/disconnection notifications drive recovery. Frame-rate configuration follows the installed SDK's supported-format and device-lock requirements for [activeVideoMinFrameDuration](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activevideominframeduration).
