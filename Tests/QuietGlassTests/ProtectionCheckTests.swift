import XCTest
import CoreVideo
@testable import QuietGlass

private final class CheckCamera: NearbyCameraSession {
    let completion: (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void
    var stopped = false
    var deviceID: String?
    init(_ completion: @escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) { self.completion = completion }
    func configureDevice(_ id: String?) { deviceID = id }
    func start() {}
    func stop() { stopped = true }
}

final class ProtectionCheckTests: XCTestCase {
    @MainActor func testCameraCoverageRequiresObservedFacesAtBothEdges() async {
        var now = 1.0, began = 0, ended = 0
        var camera: CheckCamera!
        let check = ProtectionCheck(access: { true }, makeCamera: { camera = CheckCamera($0); return camera }, clock: { now })
        check.onBegin = { began += 1 }; check.onEnd = { ended += 1 }
        check.startCamera(id: "wide-camera")
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(camera.deviceID, "wide-camera")
        let center = CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.4)
        camera.completion(.success(NearbyFaceSample(count: 1, capturedAt: now, bounds: [center])))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(check.sawCenter); XCTAssertFalse(check.sawLeft); XCTAssertFalse(check.sawRight)
        now += 0.2
        camera.completion(.success(NearbyFaceSample(count: 2, capturedAt: now, bounds: [center, CGRect(x: 0.8, y: 0.3, width: 0.15, height: 0.3)])))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(check.sawLeft); XCTAssertFalse(check.sawRight)
        now += 0.2
        camera.completion(.success(NearbyFaceSample(count: 2, capturedAt: now, bounds: [center, CGRect(x: 0.02, y: 0.3, width: 0.15, height: 0.3)])))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(check.sawRight)
        check.close(); check.close()
        XCTAssertTrue(camera.stopped); XCTAssertEqual(began, 1); XCTAssertEqual(ended, 1)
        camera.completion(.success(NearbyFaceSample(count: 1, capturedAt: now, bounds: [center])))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(check.faces.isEmpty); XCTAssertFalse(check.sawCenter)
    }

    @MainActor func testDemonstrationAutomaticallyClearsAndCanBeCancelled() {
        var now = 1.0
        var covered = false
        let check = ProtectionCheck(clock: { now })
        defer { check.close() }
        check.onDemoCoverage = { covered = $0 }
        check.demonstrate(.warning); XCTAssertEqual(check.demoSeconds, 3); XCTAssertFalse(covered)
        now = 4; check.tick(); XCTAssertTrue(covered)
        now = 7; check.tick(); XCTAssertFalse(covered); XCTAssertTrue(check.demonstrated)
        check.demonstrate(.blur); XCTAssertTrue(covered)
        check.stopDemonstration(); XCTAssertFalse(covered)
        now = 20; check.tick(); XCTAssertFalse(covered)
    }

    @MainActor func testPermissionFailureDoesNotClaimCoverageWasTested() async {
        let check = ProtectionCheck(access: { false })
        check.startCamera(id: "")
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(check.running); XCTAssertFalse(check.sawCenter)
        XCTAssertTrue(check.message.contains("Camera access")); check.close()
    }
}
