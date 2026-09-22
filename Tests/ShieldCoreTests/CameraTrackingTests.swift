import XCTest
@testable import ShieldCore

final class CameraTrackingTests: XCTestCase {
    let center = CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.3)
    let side = CGRect(x: 0.72, y: 0.35, width: 0.16, height: 0.23)
    func face(_ yaw: Double = 0, pitch: Double? = 0, bounds: CGRect? = nil) -> CameraFace {
        CameraFace(bounds: bounds ?? center, yaw: yaw, pitch: pitch)
    }
    func calibrated() -> CameraHeadPolicy {
        var p = CameraHeadPolicy()
        for n in 0...14 { p.observe([face()], at: 1 + Double(n) * 0.1, comfort: 15, transition: 18) }
        XCTAssertTrue(p.calibrated)
        return p
    }
    func testCalibrationRequiresSingleSteadyFaceAndFreshSamples() {
        var p = CameraHeadPolicy()
        for n in 0...20 { p.observe([face(), face(bounds: side)], at: Double(n) * 0.1, comfort: 15, transition: 18) }
        XCTAssertFalse(p.calibrated)
        for n in 0...20 { p.observe([face(n % 2 == 0 ? 0 : 0.15)], at: 3 + Double(n) * 0.1, comfort: 15, transition: 18) }
        XCTAssertFalse(p.calibrated)
        for n in 0...5 { p.observe([face()], at: 6 + Double(n), comfort: 15, transition: 18) }
        XCTAssertFalse(p.calibrated, "Frames far apart cannot complete calibration")
    }
    func testBriefGlanceDoesNotBlurButSustainedTurnAndReturnDo() {
        var p = calibrated()
        for n in 0...1 { p.observe([face(0.9)], at: 2.5 + Double(n) * 0.1, comfort: 15, transition: 18) }
        XCTAssertEqual(p.coverage, 0)
        for n in 0...9 { p.observe([face(0.9)], at: 2.7 + Double(n) * 0.1, comfort: 15, transition: 18) }
        XCTAssertEqual(p.coverage, 1)
        p.observe([face()], at: 3.7, comfort: 15, transition: 18)
        XCTAssertGreaterThan(p.coverage, 0)
        for n in 0...10 { p.observe([face()], at: 3.8 + Double(n) * 0.1, comfort: 15, transition: 18) }
        XCTAssertEqual(p.coverage, 0)
    }
    func testPitchTurnsAlsoBlur() {
        var p = calibrated()
        for n in 0...10 { p.observe([face(pitch: 0.9)], at: 2.5 + Double(n) * 0.1, comfort: 15, transition: 18) }
        XCTAssertEqual(p.coverage, 1)
    }
    func testMissingFaceAndStoppedFramesProtectAfterGraceAndCanRecover() {
        var p = calibrated()
        p.observe([], at: 2.6, comfort: 15, transition: 18)
        XCTAssertEqual(p.coverage, 0)
        p.tick(at: 3.1)
        XCTAssertEqual(p.coverage, 1)
        for n in 0...12 { p.observe([face()], at: 3.2 + Double(n) * 0.1, comfort: 15, transition: 18) }
        XCTAssertEqual(p.coverage, 0)
        p.tick(at: 5.2)
        XCTAssertEqual(p.coverage, 1, "No callback must not leave an old clear pose on screen")
    }
    func testFaceOrderChangesDoNotSwitchTrackedPerson() {
        var p = calibrated()
        for n in 0...10 {
            let faces = n % 2 == 0 ? [face(0.9), face(bounds: side)] : [face(bounds: side), face(0.9)]
            p.observe(faces, at: 2.5 + Double(n) * 0.1, comfort: 15, transition: 18)
        }
        XCTAssertEqual(p.coverage, 1)
    }
    func testInvalidPoseCannotCalibrateOrClearCoverage() {
        var p = calibrated(); p.fail()
        for n in 0...20 { p.observe([face(.nan)], at: 2.5 + Double(n) * 0.1, comfort: 15, transition: 18) }
        XCTAssertEqual(p.coverage, 1)
        p.beginCalibration(keepCovered: true)
        for n in 0...20 { p.observe([face(pitch: nil)], at: 5 + Double(n) * 0.1, comfort: 15, transition: 18) }
        XCTAssertFalse(p.calibrated); XCTAssertEqual(p.coverage, 1)
    }
    func testNearbySideFacingBackgroundDoesNotTriggerButForwardDwellDoes() {
        var p = NearbyAttentionPolicy()
        XCTAssertFalse(p.observe([face()], at: 1))
        for n in 0...20 {
            XCTAssertFalse(p.observe([face(), face(1.0, bounds: side)], at: 1.1 + Double(n) * 0.1))
        }
        var detected = false
        for n in 0...10 { detected = p.observe([face(), face(0, bounds: side)], at: 3.2 + Double(n) * 0.1) }
        XCTAssertTrue(detected)
    }
    func testPassersbyCannotPoolDwellAndUnknownPoseIsConservative() {
        var p = NearbyAttentionPolicy()
        _ = p.observe([face()], at: 1)
        for n in 0...20 {
            let rect = n % 2 == 0 ? side : CGRect(x: 0.05, y: 0.3, width: 0.1, height: 0.2)
            XCTAssertFalse(p.observe([face(), face(bounds: rect)], at: 1.1 + Double(n) * 0.1))
        }
        let unknown = CameraFace(bounds: side, yaw: nil, pitch: nil)
        var detected = false
        for n in 0...14 { detected = p.observe([face(), unknown], at: 3.2 + Double(n) * 0.1) }
        XCTAssertTrue(detected)
    }
    func testVerifiedOwnerCanBeSelectedAmongBackgroundFaces() {
        var p = NearbyAttentionPolicy()
        for n in 0...20 {
            XCTAssertFalse(p.observe([face(1, bounds: side), face()], ownerIndex: 1, at: 1 + Double(n) * 0.1))
        }
    }
}

extension CameraTrackingTests {
    func testCrowdedStartupUsesDominantCentralFaceButAmbiguousCrowdProtects() {
        var p = NearbyAttentionPolicy()
        for n in 0...20 {
            XCTAssertFalse(p.observe([face(), face(1, bounds: side)], at: 1 + Double(n) * 0.1))
        }
        var ambiguous = NearbyAttentionPolicy()
        let equal = CGRect(x: 0.7, y: 0.3, width: 0.2, height: 0.3)
        var result = false
        for n in 0...20 { result = ambiguous.observe([face(), face(bounds: equal)], at: 1 + Double(n) * 0.1) }
        XCTAssertTrue(result)
    }
    func testReturningWorkingFaceCanRecoverWithBackgroundStillVisible() {
        var p = calibrated()
        for n in 0...9 { p.observe([], at: 2.5 + Double(n) * 0.1, comfort: 15, transition: 18) }
        XCTAssertEqual(p.coverage, 1)
        for n in 0...12 {
            p.observe([face(), face(1, bounds: side)], at: 3.5 + Double(n) * 0.1, comfort: 15, transition: 18)
        }
        XCTAssertEqual(p.coverage, 0)
    }
    func testSingleFaceReturningAfterTrackExpiryDoesNotBecomeItsOwnObserver() {
        var p = NearbyAttentionPolicy()
        _ = p.observe([face()], at: 1)
        for n in 0...10 { _ = p.observe([], at: 1.1 + Double(n) * 0.1) }
        for n in 0...20 { XCTAssertFalse(p.observe([face()], at: 2.2 + Double(n) * 0.1)) }
    }
}
