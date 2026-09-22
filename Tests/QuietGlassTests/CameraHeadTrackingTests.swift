import XCTest
import ShieldCore
@testable import QuietGlass

private final class TrackingCamera: NearbyCameraSession {
    let completion: (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void
    var started = false
    var stopped = false
    var recognition = false
    init(_ completion: @escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) { self.completion = completion }
    func start() { started = true }
    func stop() { stopped = true }
    func configureRecognition(_ value: Bool) { recognition = value }
}

final class CameraHeadTrackingTests: XCTestCase {
    @MainActor func settle() async { for _ in 0..<20 { await Task.yield() } }
    @MainActor func testCameraDenialDoesNotStartCaptureAndStopCancelsPendingPermission() async {
        var requested = false
        let denied = CameraHeadTracking(access: { false }, makeCamera: { requested = true; return TrackingCamera($0) }, usesTimer: false)
        denied.start(deviceID: ""); await settle()
        XCTAssertEqual(denied.failure, .permission); XCTAssertFalse(requested)
        var approval: CheckedContinuation<Bool, Never>?
        let pending = CameraHeadTracking(access: { await withCheckedContinuation { approval = $0 } }, makeCamera: { requested = true; return TrackingCamera($0) }, usesTimer: false)
        pending.start(deviceID: ""); await settle(); pending.stop()
        approval?.resume(returning: true); await settle()
        XCTAssertFalse(requested); XCTAssertFalse(pending.running)
    }
    @MainActor func testFailureRetainsCoverageAndPreviousSessionCannotClearIt() async {
        var now = 1.0
        var cameras: [TrackingCamera] = []
        let tracker = CameraHeadTracking(access: { true }, makeCamera: { let c = TrackingCamera($0); cameras.append(c); return c }, clock: { now }, usesTimer: false)
        tracker.start(deviceID: ""); await settle()
        let face = CameraFace(bounds: CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.3), yaw: 0, pitch: 0)
        for n in 0...14 {
            now = 1 + Double(n) * 0.1
            cameras[0].completion(.success(NearbyFaceSample(count: 1, capturedAt: now, faces: [face])))
            await settle()
        }
        XCTAssertTrue(tracker.policy.calibrated)
        now = 3.2; tracker.tick(); XCTAssertEqual(tracker.policy.coverage, 1)
        cameras[0].completion(.failure(.disconnected)); await settle()
        XCTAssertEqual(tracker.failure, .disconnected); XCTAssertEqual(tracker.policy.coverage, 1)
        tracker.start(deviceID: ""); await settle()
        XCTAssertEqual(tracker.policy.coverage, 1)
        for n in 0...20 {
            now = 3.3 + Double(n) * 0.1
            cameras[0].completion(.success(NearbyFaceSample(count: 1, capturedAt: now, faces: [face])))
            await settle()
        }
        XCTAssertFalse(tracker.policy.calibrated); XCTAssertEqual(tracker.policy.coverage, 1)
        tracker.stop(); XCTAssertEqual(tracker.policy.coverage, 0)
        XCTAssertTrue(cameras.allSatisfy(\.stopped))
    }
    func testCameraFeedIsSharedAndReleasesOnlyAfterLastConsumer() async {
        var cameras: [TrackingCamera] = []
        let hub = FaceCameraHub(makeCamera: { let c = TrackingCamera($0); cameras.append(c); return c })
        let head = SharedFaceCamera(hub: hub) { _ in }
        let nearby = SharedFaceCamera(hub: hub) { _ in }
        head.start(); await hub.flush()
        nearby.configureRecognition(true); nearby.start(); await hub.flush()
        XCTAssertEqual(cameras.count, 1); XCTAssertTrue(cameras[0].recognition)
        head.stop(); await hub.flush(); XCTAssertFalse(cameras[0].stopped)
        nearby.stop(); await hub.flush(); XCTAssertTrue(cameras[0].stopped)
    }
    func testCameraFeedDropsStaleWorkerCallbacksAfterRestart() async {
        var cameras: [TrackingCamera] = []
        var deliveries = 0
        let hub = FaceCameraHub(makeCamera: { let c = TrackingCamera($0); cameras.append(c); return c })
        let first = SharedFaceCamera(hub: hub) { _ in deliveries += 1 }
        first.start(); await hub.flush(); first.stop(); await hub.flush()
        let second = SharedFaceCamera(hub: hub) { _ in deliveries += 1 }
        second.start(); await hub.flush()
        cameras[0].completion(.success(NearbyFaceSample(count: 1, capturedAt: 1)))
        await hub.flush(); XCTAssertEqual(deliveries, 0)
        cameras[1].completion(.success(NearbyFaceSample(count: 1, capturedAt: 2)))
        await hub.flush(); XCTAssertEqual(deliveries, 1)
        second.stop(); await hub.flush()
    }
}
