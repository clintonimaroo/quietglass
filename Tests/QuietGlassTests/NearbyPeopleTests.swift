//  Created by Clinton Imaro on 20/09/2026.

import XCTest
import SwiftUI
@testable import QuietGlass

private final class FakeFaceCamera: NearbyCameraSession {
    let completion: (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void
    var started = false
    var stopped = false
    init(_ completion: @escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) { self.completion = completion }
    func start() { started = true }
    func stop() { stopped = true }
}

@MainActor private final class NearbyHarness {
    let suite = "QuietGlass.NearbyTests.\(UUID().uuidString)"
    let preferences: UserDefaults
    var now: TimeInterval = 1
    var cameras: [FakeFaceCamera] = []
    var coverChanges: [Bool] = []
    var monitorChanges: [Bool] = []
    var nearby: NearbyPeople!

    init(access: @escaping () async -> Bool = { true }) {
        preferences = UserDefaults(suiteName: suite)!
        nearby = NearbyPeople(preferences: preferences, cameraAccess: access, makeCamera: { [unowned self] completion in
            let camera = FakeFaceCamera(completion)
            cameras.append(camera)
            return camera
        }, clock: { [unowned self] in now }, usesWatchdog: false)
        nearby.onCoverage = { [unowned self] in coverChanges.append($0) }
        nearby.onMonitoring = { [unowned self] in monitorChanges.append($0) }
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
    @MainActor func testCameraIsOffOnLaunchAndStoppingClearsBothSources() {
        let h = NearbyHarness()
        defer { h.finish() }
        XCTAssertFalse(h.nearby.enabled)
        XCTAssertFalse(h.nearby.requesting)
        XCTAssertFalse(h.nearby.covered)
        XCTAssertTrue(h.cameras.isEmpty)
        h.nearby.stop()
        XCTAssertEqual(h.coverChanges, [false])
        XCTAssertEqual(h.monitorChanges, [false])
    }

    @MainActor func testWarningNeverWarmsScreenCaptureAndPersistsOnlyTheResponse() async {
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
        XCTAssertFalse(nextLaunch.enabled)
        XCTAssertEqual(nextLaunch.status, .off)
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
