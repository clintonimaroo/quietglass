//  Created by Clinton Imaro on 20/09/2026.

import XCTest
import simd
@testable import ShieldCore

final class DisplayHeadTrackingTests: XCTestCase {
    private func yaw(_ degrees: Double) -> simd_quatd { simd_quatd(angle: degrees * .pi / 180, axis: SIMD3(0, 0, 1)) }

    func testOnlyTheDisplayBeingFacedIsClear() {
        var tracking = DisplayHeadTracking()
        tracking.calibrate(1, at: yaw(0))
        tracking.calibrate(2, at: yaw(50))
        XCTAssertEqual(tracking.coverage(current: yaw(0), displays: [1, 2], comfort: 15, transition: 18), [1: 0, 2: 1])
        XCTAssertEqual(tracking.coverage(current: yaw(50), displays: [1, 2], comfort: 15, transition: 18), [1: 1, 2: 0])
        XCTAssertEqual(tracking.coverage(current: yaw(120), displays: [1, 2], comfort: 15, transition: 18), [1: 1, 2: 1])
    }

    func testSmallMovementBetweenDisplaysDoesNotFlicker() {
        var tracking = DisplayHeadTracking()
        tracking.calibrate(1, at: yaw(0))
        tracking.calibrate(2, at: yaw(40))
        _ = tracking.coverage(current: yaw(0), displays: [1, 2], comfort: 15, transition: 18)
        _ = tracking.coverage(current: yaw(21), displays: [1, 2], comfort: 15, transition: 18)
        XCTAssertEqual(tracking.facing, 1)
        _ = tracking.coverage(current: yaw(26), displays: [1, 2], comfort: 15, transition: 18)
        XCTAssertEqual(tracking.facing, 2)
    }

    func testMissingAndDisconnectedDisplayReferencesAreNotRevealed() {
        var tracking = DisplayHeadTracking()
        tracking.calibrate(1, at: yaw(0))
        XCTAssertEqual(tracking.coverage(current: yaw(0), displays: [1, 2], comfort: 15, transition: 18), [1: 0, 2: 1])
        XCTAssertEqual(tracking.coverage(current: yaw(0), displays: [2], comfort: 15, transition: 18), [2: 1])
        tracking.invalidate()
        XCTAssertTrue(tracking.centers.isEmpty)
        XCTAssertEqual(tracking.coverage(current: yaw(0), displays: [1, 2], comfort: 15, transition: 18), [1: 1, 2: 1])
    }

    func testEscapeStaysClearUntilFacingACalibratedDisplay() {
        var tracking = DisplayHeadTracking()
        tracking.calibrate(1, at: yaw(0))
        tracking.calibrate(2, at: yaw(50))
        tracking.dismiss()
        XCTAssertEqual(tracking.coverage(current: yaw(120), displays: [1, 2], comfort: 15, transition: 18), [1: 0, 2: 0])
        XCTAssertEqual(tracking.coverage(current: yaw(50), displays: [1, 2], comfort: 15, transition: 18), [1: 0, 2: 0])
        XCTAssertEqual(tracking.coverage(current: yaw(50), displays: [1, 2], comfort: 15, transition: 18), [1: 1, 2: 0])
    }
}
