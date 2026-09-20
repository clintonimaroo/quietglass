import XCTest
import simd
@testable import ShieldCore

final class ShieldResponseTests: XCTestCase {
    func testSmallMovementsAroundTheTriggerDoNotCycleTheBlur() {
        var response = ShieldResponse(comfort: 30)
        XCTAssertEqual(response.coverage(angle: 29.9), 0)
        for angle in [30.2, 29.8, 30.1, 29.9, 28.0, 27.1] {
            XCTAssertGreaterThan(response.coverage(angle: angle), 0)
        }
        XCTAssertEqual(response.coverage(angle: 27), 0)
        XCTAssertEqual(response.coverage(angle: 29.9), 0)
        XCTAssertGreaterThan(response.coverage(angle: 30.2), 0)
    }

    func testRecenterAndEscapeClearTheTriggerHistory() {
        var response = ShieldResponse()
        _ = response.coverage(angle: 30)
        response.recenter()
        XCTAssertEqual(response.coverage(angle: 14), 0)
        _ = response.coverage(angle: 30)
        response.dismiss()
        XCTAssertEqual(response.coverage(angle: 30), 0)
        XCTAssertEqual(response.coverage(angle: 10), 0)
        XCTAssertEqual(response.coverage(angle: 14), 0)
    }

    func testLowestTriggerStillClearsWithSmallResidualHeadMotion() {
        var response = ShieldResponse(comfort: 2)
        XCTAssertGreaterThan(response.coverage(angle: 3), 0)
        XCTAssertEqual(response.coverage(angle: 0.5), 0)
        XCTAssertEqual(response.coverage(angle: 1.9), 0)
        response.dismiss()
        XCTAssertEqual(response.coverage(angle: 0.5), 0)
        XCTAssertFalse(response.dismissedUntilCentered)
        XCTAssertGreaterThan(response.coverage(angle: 3), 0)
    }

    func testAFullBlurAndClearHaveAVisibleTransition() {
        var motion = GlassTransition()
        for _ in 0..<9 { _ = motion.advance(to: 1, elapsed: 1.0 / 60) }
        XCTAssertGreaterThan(motion.value, 0.3)
        XCTAssertLessThan(motion.value, 0.8)
        for _ in 0..<60 { _ = motion.advance(to: 1, elapsed: 1.0 / 60) }
        XCTAssertEqual(motion.value, 1)
        for _ in 0..<9 { _ = motion.advance(to: 0, elapsed: 1.0 / 60) }
        XCTAssertGreaterThan(motion.value, 0.2)
        XCTAssertLessThan(motion.value, 0.7)
    }

    func testGlassMotionDoesNotDependOnSixtyVersusOneTwentyHertz() {
        var sixty = GlassTransition()
        var oneTwenty = GlassTransition()
        for _ in 0..<12 { _ = sixty.advance(to: 1, elapsed: 1.0 / 60) }
        for _ in 0..<24 { _ = oneTwenty.advance(to: 1, elapsed: 1.0 / 120) }
        XCTAssertEqual(sixty.value, oneTwenty.value, accuracy: 0.00001)
    }

    func testGlassReturnsSmoothlyAndEscapeCanResetImmediately() {
        var motion = GlassTransition()
        for _ in 0..<60 { _ = motion.advance(to: 1, elapsed: 1.0 / 60) }
        XCTAssertEqual(motion.value, 1)
        let firstReturnFrame = motion.advance(to: 0, elapsed: 1.0 / 60)
        XCTAssertGreaterThan(firstReturnFrame, 0)
        XCTAssertLessThan(firstReturnFrame, 1)
        for _ in 0..<60 { _ = motion.advance(to: 0, elapsed: 1.0 / 60) }
        XCTAssertEqual(motion.value, 0)
        _ = motion.advance(to: 1, elapsed: 1.0 / 60)
        motion.reset()
        XCTAssertEqual(motion.value, 0)
    }

    func testGlassIsEntirelyClearAtZeroAndFrostedAtFullCoverage() {
        for position in stride(from: 0.0, through: 1.0, by: 0.05) {
            XCTAssertEqual(GlassMask.opacity(position: position, coverage: 0), 0)
            XCTAssertEqual(GlassMask.opacity(position: position, coverage: 1), 1)
        }
    }

    func testGlassFeatherIsDirectionalAndMonotonic() {
        let positions = stride(from: 0.0, through: 1.0, by: 0.01).map { GlassMask.opacity(position: $0, coverage: 0.5) }
        XCTAssertEqual(positions.first, 1)
        XCTAssertEqual(positions.last, 0)
        for pair in zip(positions, positions.dropFirst()) { XCTAssertGreaterThanOrEqual(pair.0, pair.1) }
        XCTAssertGreaterThan(GlassMask.opacity(position: 0.5, coverage: 0.5), 0)
        XCTAssertLessThan(GlassMask.opacity(position: 0.5, coverage: 0.5), 1)
    }

    func testPublishedDefaultThresholdAndTransition() {
        var response = ShieldResponse()
        XCTAssertEqual(response.coverage(angle: 14), 0)
        XCTAssertEqual(response.coverage(angle: 15), 0)
        XCTAssertEqual(response.coverage(angle: 24), 0.5, accuracy: 0.0001)
        XCTAssertEqual(response.coverage(angle: 33), 1)
        XCTAssertEqual(response.coverage(angle: 170), 1)
    }

    func testEscapeDoesNotImmediatelyReshield() {
        var response = ShieldResponse()
        response.dismiss()
        XCTAssertEqual(response.coverage(angle: 40), 0)
        XCTAssertEqual(response.coverage(angle: 14), 0)
        XCTAssertTrue(response.dismissedUntilCentered)
        XCTAssertEqual(response.coverage(angle: 10), 0)
        XCTAssertFalse(response.dismissedUntilCentered)
        XCTAssertEqual(response.coverage(angle: 40), 1)
    }

    func testRecenterRearmsImmediately() {
        var response = ShieldResponse()
        response.dismiss()
        response.recenter()
        XCTAssertEqual(response.coverage(angle: 40), 1)
    }

    func testAngleWraparoundAndNonzeroCalibration() {
        let axis = SIMD3<Double>(0, 0, 1)
        let center = simd_quatd(angle: 179 * .pi / 180, axis: axis)
        let current = simd_quatd(angle: -179 * .pi / 180, axis: axis)
        let offset = HeadOffset.between(center: center, current: current)
        XCTAssertEqual(offset.angle, 2, accuracy: 0.0001)
        XCTAssertEqual(offset.yaw, 2, accuracy: 0.0001)
    }

    func testLookingUpAndSidewaysTiltAreDifferent() {
        let center = simd_quatd(angle: 0, axis: SIMD3<Double>(0, 0, 1))
        let up = simd_quatd(angle: .pi / 6, axis: SIMD3<Double>(1, 0, 0))
        let tilt = simd_quatd(angle: .pi / 6, axis: SIMD3<Double>(0, 1, 0))
        let upOffset = HeadOffset.between(center: center, current: up)
        XCTAssertEqual(upOffset.pitch, 30, accuracy: 0.0001)
        XCTAssertEqual(ShieldDirection.from(upOffset), .up)
        XCTAssertEqual(HeadOffset.between(center: center, current: tilt).angle, 0, accuracy: 0.0001)
    }

    func testBadSensorValuesDoNotLeakThroughAnActiveShield() {
        var response = ShieldResponse()
        XCTAssertEqual(response.coverage(angle: .nan), 1)
        response.dismiss()
        XCTAssertEqual(response.coverage(angle: .nan), 0)
    }
}
