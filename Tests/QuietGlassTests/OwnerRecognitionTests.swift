import XCTest
import LocalAuthentication
import Security
import AVFoundation
import ShieldCore
@testable import QuietGlass

private final class MemoryOwnerStore: OwnerTemplateStoring {
    var value: OwnerTemplate?
    var writeCount = 0
    var deleteCount = 0
    var readCount = 0
    var failWrite = false
    var containsTemplate: Bool { value != nil }
    func read(context: LAContext) throws -> OwnerTemplate {
        readCount += 1
        guard let value else { throw OwnerSetupError.missingTemplate }
        return value
    }
    func write(_ template: OwnerTemplate, context: LAContext) throws {
        if failWrite { throw OwnerSetupError.keychain(errSecIO) }
        value = template; writeCount += 1
    }
    func delete(context: LAContext) throws { value = nil; deleteCount += 1 }
}

private final class OwnerTestCamera: NearbyCameraSession {
    let previewSession: AVCaptureSession? = AVCaptureSession()
    let completion: (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void
    var started = false
    var stopped = false
    var recognition = false
    init(_ completion: @escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) { self.completion = completion }
    func start() { started = true }
    func stop() { stopped = true }
    func configureRecognition(_ enabled: Bool) { recognition = enabled }
}

@MainActor private final class OwnerRig {
    let suite = "QuietGlass.OwnerTests.\(UUID().uuidString)"
    let preferences: UserDefaults
    let store = MemoryOwnerStore()
    var owner: OwnerRecognition!
    var nearby: NearbyPeople!
    var now = 1.0
    var cameras: [OwnerTestCamera] = []
    var authCount = 0
    var denyAuth = false
    var vector: [Float] { [1] + Array(repeating: 0, count: 127) }
    var stored: OwnerTemplate { OwnerTemplate(vectors: Array(repeating: vector, count: 5), openEyes: 0.3) }
    init(enrolled: Bool = true, auth: ((String) async throws -> LAContext)? = nil) {
        preferences = UserDefaults(suiteName: suite)!
        if enrolled { store.value = stored; preferences.set(true, forKey: "ownerRecognitionEnabled") }
        owner = OwnerRecognition(preferences: preferences, store: store, authenticate: auth ?? { [unowned self] _ in
            authCount += 1
            if denyAuth { throw OwnerSetupError.authentication }
            return LAContext()
        }, cameraAccess: { true }, makeCamera: { [unowned self] result in
            let camera = OwnerTestCamera(result); cameras.append(camera); return camera
        }, clock: { [unowned self] in now })
        nearby = NearbyPeople(preferences: preferences, cameraAccess: { true }, makeCamera: { [unowned self] result in
            let camera = OwnerTestCamera(result); cameras.append(camera); return camera
        }, clock: { [unowned self] in now }, usesWatchdog: false, owner: owner)
    }
    func wait(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Asynchronous operation did not settle")
    }
    func settle() async { for _ in 0..<20 { await Task.yield() } }
    func send(pose: OwnerPose = OwnerPose(yaw: 0, eyes: 0.3), count: Int = 1, matches: Bool = true, advance: Double = 0.11) async {
        now += advance
        let value = matches ? vector : [0, 1] + Array(repeating: Float(0), count: 126)
        cameras.last!.completion(.success(NearbyFaceSample(count: count, capturedAt: now, vector: value, pose: pose)))
        await settle()
    }
    func start() async {
        nearby.setEnabled(true)
        await wait { !cameras.isEmpty || nearby.canRetry }
    }
    func passChallenge(enrollment: Bool = false) async {
        for _ in 0..<6 { await send(advance: 0.27) }
        let prompt = enrollment ? owner.prompt : nearby.ownerPrompt
        let yaw: Double = prompt.contains("left") ? 0.3 : -0.3
        for pose in [OwnerPose(yaw: yaw, eyes: 0.3), OwnerPose(yaw: 0, eyes: 0.3),
                     OwnerPose(yaw: 0, eyes: 0.05), OwnerPose(yaw: 0, eyes: 0.3)] {
            for _ in 0..<5 { await send(pose: pose) }
        }
    }
    func finish() { nearby.stop(); owner.cancelEnrollment(); preferences.removePersistentDomain(forName: suite) }
}

final class OwnerRecognitionTests: XCTestCase {
    @MainActor func testResumingSavedOwnerMonitoringRequiresAuthenticationAndANewChallenge() async {
        let h = OwnerRig(); defer { h.finish() }
        await h.start()
        await h.passChallenge()
        XCTAssertFalse(h.nearby.covered)
        let original = h.cameras[0]
        h.nearby.suspend(for: .inactiveSession)
        XCTAssertTrue(original.stopped)
        XCTAssertNil(h.owner.template)
        XCTAssertTrue(h.nearby.wantsMonitoring)
        h.nearby.resume(after: .inactiveSession)
        await h.wait { h.cameras.count == 2 }
        XCTAssertEqual(h.authCount, 2)
        XCTAssertTrue(h.nearby.covered)
        original.completion(.success(NearbyFaceSample(count: 1, capturedAt: h.now, vector: h.vector, pose: OwnerPose(yaw: 0, eyes: 0.3))))
        for _ in 0..<20 { await h.send() }
        XCTAssertTrue(h.nearby.covered)
        await h.passChallenge()
        XCTAssertFalse(h.nearby.covered)
    }

    @MainActor func testOwnerStartsCoveredAndDifferentSingleFaceNeverClears() async {
        let h = OwnerRig(); defer { h.finish() }
        XCTAssertTrue(h.cameras.isEmpty)
        XCTAssertNil(h.owner.template)
        h.nearby.setEnabled(true)
        XCTAssertTrue(h.nearby.covered)
        await h.wait { !h.cameras.isEmpty }
        XCTAssertTrue(h.cameras[0].recognition)
        await h.passChallenge()
        XCTAssertFalse(h.nearby.covered)
        for _ in 0..<30 { await h.send(matches: false) }
        XCTAssertTrue(h.nearby.covered)
        XCTAssertEqual(h.nearby.noticeTitle, "Owner not verified")
        await h.passChallenge()
        XCTAssertFalse(h.nearby.covered)
        XCTAssertEqual(h.authCount, 1)
        h.nearby.stop()
        XCTAssertNil(h.owner.template)
        XCTAssertTrue(h.cameras[0].stopped)
    }

    @MainActor func testCameraLossWhileOwnerWasClearCoversAndRetryNeedsNewChallenge() async {
        let h = OwnerRig(); defer { h.finish() }
        await h.start(); await h.passChallenge()
        XCTAssertFalse(h.nearby.covered)
        let old = h.cameras[0]
        old.completion(.failure(.disconnected)); await h.settle()
        XCTAssertTrue(h.nearby.covered)
        XCTAssertNil(h.owner.template)
        h.nearby.retry()
        await h.wait { h.cameras.count == 2 }
        XCTAssertEqual(h.authCount, 2)
        old.completion(.success(NearbyFaceSample(count: 1, capturedAt: h.now, vector: h.vector, pose: OwnerPose(yaw: 0, eyes: 0.3))))
        for _ in 0..<20 { await h.send() }
        XCTAssertTrue(h.nearby.covered, "A matching still face alone must not clear after retry")
        await h.passChallenge()
        XCTAssertFalse(h.nearby.covered)
    }

    @MainActor func testMultipleFacesAndNoFaceResetOwnerCheck() async {
        let h = OwnerRig(); defer { h.finish() }
        await h.start(); await h.passChallenge()
        for _ in 0..<6 { await h.send(count: 2) }
        XCTAssertTrue(h.nearby.covered)
        for _ in 0..<20 { await h.send(count: 0) }
        XCTAssertTrue(h.nearby.covered)
        await h.passChallenge()
        XCTAssertFalse(h.nearby.covered)
    }

    @MainActor func testDeniedOrMissingKeychainAccessCannotFallBackToFaceCount() async {
        let h = OwnerRig(); defer { h.finish() }
        h.denyAuth = true
        await h.start()
        XCTAssertTrue(h.cameras.isEmpty)
        XCTAssertTrue(h.nearby.covered)
        XCTAssertEqual(h.nearby.status, .unavailable(.ownerAccess))
        XCTAssertTrue(h.nearby.enabled, "A retained owner blur must still have an active stop toggle")
        h.denyAuth = false; h.store.value = nil
        h.nearby.retry()
        await h.wait { h.nearby.canRetry }
        XCTAssertTrue(h.nearby.covered)
        XCTAssertTrue(h.cameras.isEmpty)
        XCTAssertTrue(h.owner.enabled)
    }

    @MainActor func testStopDuringAuthenticationCannotOpenCameraOrRetainTemplate() async {
        var continuation: CheckedContinuation<LAContext, Error>?
        let h = OwnerRig(auth: { _ in try await withCheckedThrowingContinuation { continuation = $0 } })
        defer { h.finish() }
        h.nearby.setEnabled(true)
        await h.wait { continuation != nil }
        h.nearby.stop()
        continuation?.resume(returning: LAContext())
        await h.settle()
        XCTAssertNil(h.owner.template)
        XCTAssertTrue(h.cameras.isEmpty)
        XCTAssertFalse(h.nearby.covered)
    }

    @MainActor func testWarningModeVerifiesOwnerWithoutRequestingBlur() async {
        let h = OwnerRig(); defer { h.finish() }
        h.nearby.setResponse(.warning)
        var requestedCapture = false
        h.nearby.onMonitoring = { if $0 { requestedCapture = true } }
        await h.start()
        XCTAssertTrue(h.nearby.alertActive)
        XCTAssertFalse(h.nearby.covered)
        await h.passChallenge()
        XCTAssertFalse(h.nearby.alertActive)
        XCTAssertFalse(requestedCapture)
    }

    @MainActor func testEnrollmentDoesNotSaveUntilConfirmedAndDeletesAfterAuthentication() async {
        let h = OwnerRig(enrolled: false); defer { h.finish() }
        h.owner.beginEnrollment()
        await h.wait { h.owner.enrolling }
        XCTAssertTrue(h.owner.previewSession === h.cameras[0].previewSession)
        for _ in 0..<5 { await h.send(advance: 0.3) }
        await h.passChallenge(enrollment: true)
        XCTAssertTrue(h.owner.readyToSave)
        XCTAssertNil(h.owner.previewSession)
        XCTAssertNil(h.store.value)
        XCTAssertTrue(h.cameras[0].stopped)
        h.owner.saveEnrollment()
        await h.wait { !h.owner.busy }
        XCTAssertTrue(h.owner.enrolled)
        XCTAssertTrue(h.owner.enabled)
        XCTAssertEqual(h.store.writeCount, 1)
        XCTAssertNil(h.owner.template, "Stored embeddings should not be kept between sessions")
        h.owner.deleteEnrollment()
        await h.wait { !h.owner.busy }
        XCTAssertNil(h.store.value)
        XCTAssertFalse(h.owner.enrolled)
        XCTAssertFalse(h.owner.enabled)
        XCTAssertEqual(h.authCount, 2)
        XCTAssertEqual(h.store.deleteCount, 1)
    }

    @MainActor func testCancelledOrFailedEnrollmentLeavesExistingFaceUntouched() async {
        let h = OwnerRig(); defer { h.finish() }
        h.owner.beginEnrollment()
        await h.wait { h.owner.enrolling }
        await h.send()
        h.owner.cancelEnrollment()
        XCTAssertNil(h.owner.previewSession)
        XCTAssertEqual(h.store.value, h.stored)
        XCTAssertEqual(h.store.writeCount, 0)
        XCTAssertTrue(h.cameras[0].stopped)
        h.denyAuth = true
        h.owner.deleteEnrollment()
        await h.wait { !h.owner.busy }
        XCTAssertEqual(h.store.value, h.stored)
        XCTAssertTrue(h.owner.enabled)
        XCTAssertEqual(h.store.deleteCount, 0)
    }

    @MainActor func testFailedReplacementWritePreservesSavedTemplate() async {
        let h = OwnerRig(); defer { h.finish() }
        h.owner.beginEnrollment()
        await h.wait { h.owner.enrolling }
        for _ in 0..<5 { await h.send(advance: 0.3) }
        await h.passChallenge(enrollment: true)
        XCTAssertTrue(h.owner.readyToSave)
        h.store.failWrite = true
        h.owner.saveEnrollment()
        await h.wait { !h.owner.busy }
        XCTAssertEqual(h.store.value, h.stored)
        XCTAssertEqual(h.store.writeCount, 0)
        XCTAssertTrue(h.owner.enrolled)
        XCTAssertNotNil(h.owner.error)
        XCTAssertFalse(h.owner.enrolling)
    }

    @MainActor func testWatchdogAndDuplicateFramesDoNotLeaveOwnerModeClear() async {
        let h = OwnerRig(); defer { h.finish() }
        await h.start(); await h.passChallenge()
        XCTAssertFalse(h.nearby.covered)
        let oldTimestamp = h.now
        h.now += 5
        h.cameras[0].completion(.success(NearbyFaceSample(count: 1, capturedAt: oldTimestamp, vector: h.vector, pose: OwnerPose(yaw: 0, eyes: 0.3))))
        await h.settle()
        h.nearby.checkCameraHealth()
        XCTAssertEqual(h.nearby.status, .unavailable(.stalled))
        XCTAssertTrue(h.nearby.covered)
        XCTAssertNil(h.owner.template)
    }

    func testRealKeychainRoundTripInAnIsolatedTemporaryKeychain() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QuietGlass-Keychain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let password = UUID().uuidString
        var keychain: SecKeychain?
        let status = password.withCString { pointer in
            SecKeychainCreate(directory.appendingPathComponent("test.keychain-db").path, UInt32(password.utf8.count), pointer, false, nil, &keychain)
        }
        XCTAssertEqual(status, errSecSuccess)
        let isolated = try XCTUnwrap(keychain)
        defer { SecKeychainDelete(isolated) }
        let store = OwnerTemplateStore(keychain: isolated)
        let vector: [Float] = [1] + Array(repeating: 0, count: 127)
        let original = OwnerTemplate(vectors: Array(repeating: vector, count: 5), openEyes: 0.3)
        XCTAssertFalse(store.containsTemplate)
        try store.write(original, context: LAContext())
        XCTAssertTrue(store.containsTemplate)
        XCTAssertEqual(try store.read(context: LAContext()), original)
        let replacement = OwnerTemplate(vectors: Array(repeating: vector, count: 5), openEyes: 0.28)
        try store.write(replacement, context: LAContext())
        XCTAssertEqual(try store.read(context: LAContext()), replacement)
        XCTAssertThrowsError(try store.write(OwnerTemplate(vectors: [], openEyes: 0.3), context: LAContext()))
        XCTAssertEqual(try store.read(context: LAContext()), replacement)
        try store.delete(context: LAContext())
        XCTAssertFalse(store.containsTemplate)
        XCTAssertThrowsError(try store.read(context: LAContext()))
    }
}
