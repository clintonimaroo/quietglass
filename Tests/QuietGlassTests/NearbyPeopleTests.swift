//  Created by Clinton Imaro on 20/09/2026.

import XCTest
import SwiftUI
@testable import QuietGlass

private final class FakeFaceCamera: NearbyCameraSession {
    let completion: (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void
    var started = false
    var stopped = false
    var deviceID: String?
    init(_ completion: @escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) { self.completion = completion }
    func start() { started = true }
    func stop() { stopped = true }
    func configureDevice(_ id: String?) { deviceID = id }
}

@MainActor private final class NearbyHarness {
    let suite = "QuietGlass.NearbyTests.\(UUID().uuidString)"
    let preferences: UserDefaults
    var now: TimeInterval = 1
    var wallOffset: TimeInterval = 0
    var cameras: [FakeFaceCamera] = []
    var coverChanges: [Bool] = []
    var monitorChanges: [Bool] = []
    var nearby: NearbyPeople!
    let access: () async -> Bool

    init(access: @escaping () async -> Bool = { true }) {
        self.access = access
        preferences = UserDefaults(suiteName: suite)!
        createNearby()
    }

    func createNearby() {
        nearby = NearbyPeople(preferences: UserDefaults(suiteName: suite)!, cameraAccess: access, makeCamera: { [unowned self] completion in
            let camera = FakeFaceCamera(completion)
            cameras.append(camera)
            return camera
        }, clock: { [unowned self] in now }, wallClock: { [unowned self] in Date(timeIntervalSince1970: now + wallOffset) }, usesWatchdog: false)
        nearby.onCoverage = { [unowned self] in coverChanges.append($0) }
        nearby.onMonitoring = { [unowned self] in monitorChanges.append($0) }
    }

    func relaunch() {
        nearby.shutdown()
        createNearby()
    }

    func start() async {
        nearby.setEnabled(true)
        await settle()
    }

    func send(_ count: Int, at time: TimeInterval) async {
        now = time
        cameras.last!.completion(.success(NearbyFaceSample(count: count, capturedAt: time)))
        await settle()
    }

    func settle() async { for _ in 0..<10 { await Task.yield() } }
    func finish() {
        nearby.stop()
        preferences.removePersistentDomain(forName: suite)
    }
}

final class NearbyPeopleTests: XCTestCase {
    @MainActor func testImmediateBlurDoesNotChangeWarningPreferenceAndNeedsSteadyClear() async {
        let h = NearbyHarness(); defer { h.finish() }
        h.nearby.setResponse(.warning); await h.start()
        await h.send(2, at: 1); await h.send(2, at: 1.4)
        h.nearby.blurNow()
        XCTAssertTrue(h.nearby.covered); XCTAssertEqual(h.nearby.response, .warning)
        await h.send(1, at: 2); await h.send(1, at: 2.8)
        XCTAssertTrue(h.nearby.covered)
        await h.send(1, at: 3.6)
        XCTAssertFalse(h.nearby.covered)
    }

    @MainActor func testTimedPauseStopsCameraAndResumesAtDeadlineWithoutStaleCallbacks() async {
        let h = NearbyHarness(); defer { h.finish() }
        await h.start(); let original = h.cameras[0]
        h.nearby.pauseForFiveMinutes()
        XCTAssertTrue(original.stopped); XCTAssertFalse(h.nearby.enabled)
        XCTAssertTrue(h.nearby.wantsMonitoring); XCTAssertEqual(h.nearby.pauseSecondsRemaining, 300)
        original.completion(.success(NearbyFaceSample(count: 2, capturedAt: 1.4))); await h.settle()
        XCTAssertFalse(h.nearby.covered)
        h.now = 300; h.nearby.updatePauseDeadline()
        XCTAssertEqual(h.nearby.pauseSecondsRemaining, 1)
        h.now = 301; h.nearby.updatePauseDeadline(); await h.settle()
        XCTAssertEqual(h.cameras.count, 2); XCTAssertTrue(h.nearby.enabled)
        XCTAssertFalse(h.nearby.temporarilyPaused)
    }

    @MainActor func testPauseSurvivesRelaunchAndStopCancelsAutomaticResume() async {
        let h = NearbyHarness(); defer { h.finish() }
        await h.start(); h.nearby.pauseForFiveMinutes()
        h.now = 101; h.relaunch(); h.nearby.restore(); await h.settle()
        XCTAssertEqual(h.nearby.pauseSecondsRemaining, 200); XCTAssertEqual(h.cameras.count, 1)
        h.nearby.stop(); h.now = 400; h.nearby.updatePauseDeadline(); h.nearby.restore(); await h.settle()
        XCTAssertFalse(h.nearby.wantsMonitoring); XCTAssertEqual(h.cameras.count, 1)
    }

    @MainActor func testPauseExpiresDuringSleepWithoutStartingCameraUntilWake() async {
        let h = NearbyHarness(); defer { h.finish() }
        await h.start(); h.nearby.pauseForFiveMinutes(); h.nearby.suspend(for: .systemSleep)
        h.now = 302; h.nearby.updatePauseDeadline(); await h.settle()
        XCTAssertFalse(h.nearby.enabled); XCTAssertEqual(h.cameras.count, 1)
        h.nearby.resume(after: .systemSleep); await h.settle()
        XCTAssertTrue(h.nearby.enabled); XCTAssertEqual(h.cameras.count, 2)
    }

    @MainActor func testBackwardWallClockChangeCannotExtendTimedPause() async {
        let h = NearbyHarness(); defer { h.finish() }
        await h.start(); h.nearby.pauseForFiveMinutes()
        h.wallOffset = -3600; h.now = 301
        h.nearby.updatePauseDeadline(); await h.settle()
        XCTAssertFalse(h.nearby.temporarilyPaused); XCTAssertTrue(h.nearby.enabled)
    }

    @MainActor func testCameraSelectionPersistsAndReconfiguresMonitoring() async {
        let h = NearbyHarness(); defer { h.finish() }
        h.nearby.selectCamera("external-test-camera"); await h.start()
        XCTAssertEqual(h.cameras.last?.deviceID, "external-test-camera")
        let first = h.cameras[0]
        h.nearby.selectCamera(""); await h.settle()
        XCTAssertTrue(first.stopped); XCTAssertEqual(h.cameras.last?.deviceID, "")
        h.nearby.selectCamera("external-test-camera"); await h.settle(); h.relaunch()
        XCTAssertEqual(h.nearby.selectedCameraID, "external-test-camera")
    }
    @MainActor func testWarningSoundDefaultsOnAndRemembersMuteAcrossRelaunch() {
        let h = NearbyHarness()
        defer { h.finish() }
        XCTAssertTrue(h.nearby.warningSoundEnabled)
        h.nearby.setWarningSoundEnabled(false)
        h.relaunch()
        XCTAssertFalse(h.nearby.warningSoundEnabled)
        h.nearby.setWarningSoundEnabled(true)
        h.relaunch()
        XCTAssertTrue(h.nearby.warningSoundEnabled)
        XCTAssertTrue(h.cameras.isEmpty, "Changing sound settings must not start the camera")
    }

    @MainActor func testEnablingDetectionPersistsTheUserChoice() async {
        let h = NearbyHarness()
        defer { h.finish() }
        await h.start()
        let reopenedPreferences = UserDefaults(suiteName: h.suite)!
        XCTAssertTrue(reopenedPreferences.bool(forKey: "nearbyEnabled"))
    }

    @MainActor func testCameraIsOffOnLaunchAndStoppingClearsBothSources() {
        let h = NearbyHarness()
        defer { h.finish() }
        XCTAssertFalse(h.nearby.enabled)
        XCTAssertFalse(h.nearby.requesting)
        XCTAssertFalse(h.nearby.covered)
        XCTAssertFalse(h.nearby.wantsMonitoring)
        h.nearby.restore()
        XCTAssertTrue(h.cameras.isEmpty)
        h.nearby.stop()
        XCTAssertEqual(h.coverChanges, [false])
        XCTAssertEqual(h.monitorChanges, [false])
    }

    @MainActor func testWarningWaitsBeforeScreenCaptureAndPersistsTheResponse() async {
        let h = NearbyHarness()
        defer { h.finish() }
        h.nearby.setResponse(.warning)
        await h.start()
        await h.send(2, at: 1)
        await h.send(2, at: 1.4)
        XCTAssertTrue(h.nearby.alertActive)
        XCTAssertTrue(h.nearby.needsAttention)
        XCTAssertFalse(h.nearby.covered)
        XCTAssertTrue(h.coverChanges.isEmpty)
        XCTAssertTrue(h.monitorChanges.isEmpty)
        let nextLaunch = NearbyPeople(preferences: h.preferences)
        XCTAssertEqual(nextLaunch.response, .warning)
        XCTAssertTrue(nextLaunch.wantsMonitoring)
        XCTAssertFalse(nextLaunch.enabled)
        XCTAssertEqual(nextLaunch.status, .off)
    }

    @MainActor func testUnresolvedWarningBlursAfterTwoMinutesWithoutAnotherCameraFrame() async {
        let h = NearbyHarness(); defer { h.finish() }
        h.nearby.setResponse(.warning)
        await h.start()
        await h.send(2, at: 1)
        await h.send(2, at: 1.4)
        XCTAssertEqual(h.nearby.warningSecondsRemaining, 120)
        h.now = 121.3
        h.nearby.checkWarningDeadline()
        XCTAssertFalse(h.nearby.covered)
        XCTAssertTrue(h.monitorChanges.isEmpty)
        h.now = 121.5
        h.nearby.checkWarningDeadline()
        XCTAssertTrue(h.nearby.covered)
        XCTAssertTrue(h.nearby.requiresBlur)
        XCTAssertEqual(h.coverChanges, [true])
        XCTAssertEqual(h.monitorChanges, [true])
        h.nearby.checkWarningDeadline()
        XCTAssertEqual(h.coverChanges, [true])
        await h.send(1, at: 122)
        await h.send(1, at: 122.8)
        XCTAssertTrue(h.nearby.covered)
        await h.send(1, at: 123.6)
        XCTAssertFalse(h.nearby.covered)
        XCTAssertNil(h.nearby.warningSecondsRemaining)
        XCTAssertEqual(h.monitorChanges, [true, false])
    }

    @MainActor func testResolvingOrStoppingWarningCancelsItsDeadline() async {
        let h = NearbyHarness(); defer { h.finish() }
        h.nearby.setResponse(.warning)
        await h.start()
        await h.send(2, at: 1)
        await h.send(2, at: 1.4)
        await h.send(1, at: 2)
        await h.send(1, at: 2.8)
        await h.send(1, at: 3.6)
        h.now = 200
        h.nearby.checkWarningDeadline()
        XCTAssertFalse(h.nearby.covered)
        XCTAssertNil(h.nearby.warningSecondsRemaining)
        await h.send(2, at: 201)
        await h.send(2, at: 201.4)
        XCTAssertEqual(h.nearby.warningSecondsRemaining, 120)
        h.nearby.stop()
        h.now = 400
        h.nearby.checkWarningDeadline()
        XCTAssertFalse(h.nearby.covered)
        XCTAssertNil(h.nearby.warningSecondsRemaining)
    }

    @MainActor func testWarningTimerRunsWithoutCameraCallbacks() async throws {
        let h = NearbyHarness(); defer { h.finish() }
        h.nearby.setResponse(.warning)
        await h.start()
        await h.send(2, at: 1)
        await h.send(2, at: 1.4)
        h.now += 121
        // Advance the injected clock, then let the real timer deliver its tick.
        // No sample or explicit deadline check may cause this transition.
        for _ in 0..<20 {
            if h.nearby.covered { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(h.nearby.covered)
        XCTAssertEqual(h.nearby.warningSecondsRemaining, 0)
        XCTAssertEqual(h.coverChanges, [true])
    }

    @MainActor func testDurationPersistsAndEditingItDoesNotReleaseExistingBlur() async {
        let h = NearbyHarness(); defer { h.finish() }
        XCTAssertEqual(h.nearby.warningDelay, 120)
        h.nearby.setWarningDelay(180)
        h.relaunch()
        XCTAssertEqual(h.nearby.warningDelay, 180)
        h.nearby.setResponse(.warning)
        await h.start()
        await h.send(2, at: 1)
        await h.send(2, at: 1.4)
        h.now = 91.4
        h.nearby.setWarningDelay(60)
        XCTAssertTrue(h.nearby.covered)
        h.nearby.setWarningDelay(300)
        XCTAssertTrue(h.nearby.covered)
        XCTAssertEqual(h.nearby.warningSecondsRemaining, 0)
        h.nearby.suspend(for: .systemSleep)
        h.now = 600
        h.nearby.checkWarningDeadline()
        XCTAssertFalse(h.nearby.covered)
        XCTAssertNil(h.nearby.warningSecondsRemaining)
        XCTAssertEqual(h.nearby.warningDelay, 300)
    }

    @MainActor func testCameraFailureCountdownAndRetryKeepBlurUntilAStableFaceReturns() async {
        let h = NearbyHarness(); defer { h.finish() }
        h.nearby.setResponse(.warning)
        await h.start()
        h.cameras[0].completion(.failure(.interrupted))
        await h.settle()
        XCTAssertEqual(h.nearby.warningSecondsRemaining, 120)
        h.now += 121
        h.nearby.checkWarningDeadline()
        XCTAssertTrue(h.nearby.covered)
        h.nearby.retry()
        await h.settle()
        XCTAssertTrue(h.nearby.covered)
        await h.send(1, at: 123)
        XCTAssertTrue(h.nearby.covered)
        await h.send(1, at: 123.8)
        await h.send(1, at: 124.6)
        XCTAssertFalse(h.nearby.covered)
        XCTAssertNil(h.nearby.warningSecondsRemaining)
    }

    @MainActor func testRelaunchRestoresSavedDetectionAfterCallbacksAreConnected() async {
        let h = NearbyHarness()
        defer { h.finish() }
        h.nearby.setResponse(.warning)
        await h.start()
        let original = h.cameras[0]
        h.relaunch()
        XCTAssertTrue(original.stopped)
        XCTAssertTrue(h.nearby.wantsMonitoring)
        XCTAssertFalse(h.nearby.enabled)
        XCTAssertEqual(h.cameras.count, 1, "Initialization must not start the camera before callbacks are ready")
        h.nearby.restore()
        await h.settle()
        XCTAssertTrue(h.nearby.enabled)
        XCTAssertTrue(h.cameras.last!.started)
        XCTAssertEqual(h.cameras.count, 2)
        XCTAssertEqual(h.nearby.response, .warning)
        XCTAssertFalse(h.nearby.covered)
        h.nearby.restore()
        await h.settle()
        XCTAssertEqual(h.cameras.count, 2, "Restoring an active setting must not start another session")
    }

    @MainActor func testExplicitOffAndEscapeStopStayOffAcrossRelaunch() async {
        let h = NearbyHarness()
        defer { h.finish() }
        for useToggle in [true, false] {
            await h.start()
            if useToggle { h.nearby.setEnabled(false) }
            else { h.nearby.stop() } // AppModel.dismissShield uses this for Escape.
            let cameraCount = h.cameras.count
            h.relaunch()
            h.nearby.restore()
            await h.settle()
            XCTAssertFalse(h.nearby.wantsMonitoring)
            XCTAssertFalse(h.nearby.enabled)
            XCTAssertFalse(h.preferences.bool(forKey: "nearbyEnabled"))
            XCTAssertEqual(h.cameras.count, cameraCount)
        }
    }

    @MainActor func testSleepAndSessionPausesPreserveSelectionUntilEveryReasonClears() async {
        let h = NearbyHarness()
        defer { h.finish() }
        await h.start()
        let original = h.cameras[0]
        h.nearby.suspend(for: .systemSleep)
        h.nearby.suspend(for: .displaySleep)
        h.nearby.suspend(for: .inactiveSession)
        XCTAssertTrue(original.stopped)
        XCTAssertTrue(h.nearby.wantsMonitoring)
        XCTAssertTrue(h.preferences.bool(forKey: "nearbyEnabled"))
        XCTAssertEqual(h.nearby.status, .paused)
        original.completion(.success(NearbyFaceSample(count: 2, capturedAt: 1)))
        await h.settle()
        XCTAssertFalse(h.nearby.covered)
        h.nearby.resume(after: .systemSleep)
        h.nearby.resume(after: .displaySleep)
        await h.settle()
        XCTAssertFalse(h.nearby.enabled)
        XCTAssertEqual(h.cameras.count, 1)
        h.nearby.resume(after: .inactiveSession)
        await h.settle()
        XCTAssertTrue(h.nearby.enabled)
        XCTAssertEqual(h.cameras.count, 2)
        h.nearby.resume(after: .inactiveSession)
        await h.settle()
        XCTAssertEqual(h.cameras.count, 2)
    }

    @MainActor func testTurningOffWhilePausedPreventsWakeAndLaunchRestart() async {
        let h = NearbyHarness()
        defer { h.finish() }
        await h.start()
        h.nearby.suspend(for: .displaySleep)
        h.nearby.setEnabled(false)
        h.nearby.resume(after: .displaySleep)
        h.relaunch()
        h.nearby.restore()
        await h.settle()
        XCTAssertEqual(h.cameras.count, 1)
        XCTAssertFalse(h.nearby.wantsMonitoring)
        XCTAssertFalse(h.nearby.enabled)
    }

    @MainActor func testSavedSelectionSurvivesStartupFailureAndRetriesThroughPreparation() async {
        let h = NearbyHarness()
        defer { h.finish() }
        await h.start()
        h.relaunch()
        var preparationFailure: NearbyCameraFailure? = .screenPermission
        h.nearby.prepareMonitoring = { preparationFailure }
        h.nearby.restore()
        await h.settle()
        XCTAssertTrue(h.nearby.wantsMonitoring)
        XCTAssertTrue(h.nearby.canRetry)
        XCTAssertEqual(h.nearby.status, .unavailable(.screenPermission))
        XCTAssertEqual(h.cameras.count, 1)
        preparationFailure = .escapeUnavailable
        h.nearby.retry()
        await h.settle()
        XCTAssertEqual(h.nearby.status, .unavailable(.escapeUnavailable))
        XCTAssertEqual(h.cameras.count, 1)
        preparationFailure = nil
        h.nearby.retry()
        await h.settle()
        XCTAssertTrue(h.nearby.enabled)
        XCTAssertEqual(h.cameras.count, 2)
    }

    @MainActor func testSuspendingPendingPermissionIgnoresItsLateResult() async {
        var continuation: CheckedContinuation<Bool, Never>?
        var requests = 0
        let h = NearbyHarness(access: {
            requests += 1
            if requests == 1 { return await withCheckedContinuation { continuation = $0 } }
            return true
        })
        defer { h.finish() }
        await h.start()
        XCTAssertNotNil(continuation)
        h.nearby.suspend(for: .systemSleep)
        continuation?.resume(returning: true)
        await h.settle()
        XCTAssertTrue(h.cameras.isEmpty)
        XCTAssertTrue(h.nearby.wantsMonitoring)
        h.nearby.resume(after: .systemSleep)
        await h.settle()
        XCTAssertEqual(h.cameras.count, 1)
        XCTAssertTrue(h.nearby.enabled)
    }

    @MainActor func testBlurWaitsForStableDetectionAndDoesNotFlickerThroughMissingFaces() async {
        let h = NearbyHarness()
        defer { h.finish() }
        await h.start()
        XCTAssertEqual(h.monitorChanges, [true])
        await h.send(2, at: 1)
        await h.send(1, at: 1.2)
        XCTAssertFalse(h.nearby.covered)
        await h.send(2, at: 1.4)
        await h.send(2, at: 1.8)
        XCTAssertTrue(h.nearby.covered)
        await h.send(0, at: 2)
        await h.send(1, at: 2.4)
        await h.send(1, at: 3.2)
        XCTAssertTrue(h.nearby.covered)
        await h.send(1, at: 4)
        XCTAssertFalse(h.nearby.covered)
        XCTAssertEqual(h.coverChanges, [true, false])
    }

    @MainActor func testChangingResponseWhileAlertedUpdatesOnlyNearbyProtection() async {
        let h = NearbyHarness()
        defer { h.finish() }
        h.nearby.setResponse(.warning)
        await h.start()
        await h.send(2, at: 1)
        await h.send(2, at: 1.4)
        h.nearby.setResponse(.blur)
        XCTAssertTrue(h.nearby.covered)
        XCTAssertEqual(h.monitorChanges, [true])
        h.nearby.setResponse(.warning)
        XCTAssertTrue(h.nearby.alertActive)
        XCTAssertFalse(h.nearby.covered)
        XCTAssertEqual(h.coverChanges, [true, false])
        XCTAssertEqual(h.monitorChanges, [true, false])
    }

    @MainActor func testCameraFailureAndRetryCannotReleaseExistingBlur() async {
        let h = NearbyHarness()
        defer { h.finish() }
        await h.start()
        await h.send(2, at: 1)
        await h.send(2, at: 1.4)
        let original = h.cameras[0]
        original.completion(.failure(.disconnected))
        await h.settle()
        XCTAssertTrue(original.stopped)
        XCTAssertTrue(h.nearby.canRetry)
        XCTAssertTrue(h.nearby.covered)
        h.nearby.retry()
        await h.settle()
        XCTAssertEqual(h.cameras.count, 2)
        XCTAssertTrue(h.nearby.covered)
        original.completion(.failure(.configuration))
        original.completion(.success(NearbyFaceSample(count: 1, capturedAt: 1.4)))
        await h.settle()
        XCTAssertEqual(h.nearby.status, .starting)
        await h.send(1, at: 2)
        await h.send(1, at: 2.8)
        XCTAssertTrue(h.nearby.covered)
        await h.send(1, at: 3.6)
        XCTAssertFalse(h.nearby.covered)
        XCTAssertEqual(h.coverChanges, [true, false])
        XCTAssertEqual(h.monitorChanges, [true])
    }

    @MainActor func testStaleFramesCannotTriggerBlurOrKeepADeadCameraHealthy() async {
        let h = NearbyHarness()
        defer { h.finish() }
        await h.start()
        h.now = 6
        h.cameras[0].completion(.success(NearbyFaceSample(count: 2, capturedAt: 2)))
        await h.settle()
        h.nearby.checkCameraHealth()
        XCTAssertEqual(h.nearby.status, .unavailable(.stalled))
        XCTAssertFalse(h.nearby.covered)
        XCTAssertEqual(h.monitorChanges, [true, false])
        XCTAssertTrue(h.cameras[0].stopped)
    }

    @MainActor func testDeniedPermissionShowsRecoveryWithoutStartingACamera() async {
        let h = NearbyHarness(access: { false })
        defer { h.finish() }
        await h.start()
        XCTAssertTrue(h.cameras.isEmpty)
        XCTAssertFalse(h.nearby.enabled)
        XCTAssertTrue(h.nearby.needsCameraPermission)
        XCTAssertTrue(h.nearby.wantsMonitoring, "A permission failure must not change the user's switch")
        XCTAssertTrue(h.nearby.canRetry)
        XCTAssertTrue(h.monitorChanges.isEmpty)
    }

    @MainActor func testStopWhilePermissionIsPendingCannotStartTheCameraLater() async {
        var continuation: CheckedContinuation<Bool, Never>?
        let h = NearbyHarness(access: { await withCheckedContinuation { continuation = $0 } })
        defer { h.finish() }
        await h.start()
        XCTAssertTrue(h.nearby.requesting)
        XCTAssertNotNil(continuation)
        h.nearby.stop()
        continuation?.resume(returning: true)
        await h.settle()
        XCTAssertTrue(h.cameras.isEmpty)
        XCTAssertEqual(h.nearby.status, .off)
        XCTAssertFalse(h.nearby.enabled)
    }

    @MainActor func testStopIgnoresLateCameraCallbacksAndReenableStartsFresh() async {
        let h = NearbyHarness()
        defer { h.finish() }
        await h.start()
        let original = h.cameras[0]
        await h.send(2, at: 1)
        await h.send(2, at: 1.4)
        h.nearby.stop()
        original.completion(.success(NearbyFaceSample(count: 2, capturedAt: 1.8)))
        await h.settle()
        XCTAssertEqual(h.nearby.status, .off)
        XCTAssertFalse(h.nearby.alertActive)
        await h.start()
        XCTAssertEqual(h.nearby.status, .starting)
        XCTAssertFalse(h.nearby.covered)
    }

    @MainActor func testCameraFailureInWarningModeShowsAttentionWithoutBlur() async {
        let h = NearbyHarness()
        defer { h.finish() }
        h.nearby.setResponse(.warning)
        await h.start()
        h.cameras[0].completion(.failure(.interrupted))
        await h.settle()
        XCTAssertTrue(h.nearby.needsAttention)
        XCTAssertEqual(h.nearby.noticeTitle, "Camera interrupted")
        XCTAssertFalse(h.nearby.covered)
        XCTAssertTrue(h.monitorChanges.isEmpty)
        XCTAssertTrue(h.coverChanges.isEmpty)
    }

    @MainActor func testUnavailableEscapeReportsProtectionFailureInsteadOfReady() {
        let privacy = PrivacyController()
        defer { privacy.shutdown() }
        privacy.requestEscape = { false }
        privacy.setNearbyMonitoring(true)
        XCTAssertTrue(privacy.captureUnavailable)
        XCTAssertFalse(privacy.ready)
        XCTAssertFalse(privacy.nearbyCovered)
        XCTAssertEqual(privacy.notice, "Escape is unavailable. Protection is paused.")
    }
}
