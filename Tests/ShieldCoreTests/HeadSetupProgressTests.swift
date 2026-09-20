//  Created by Clinton Imaro on 20/09/2026.

import XCTest
@testable import ShieldCore

final class HeadSetupProgressTests: XCTestCase {
    func testRequiresSustainedMotionInAllFourDirections() {
        var progress = HeadSetupProgress()
        var time = 0.0
        for offset in [HeadOffset(yaw: 12, pitch: 0), HeadOffset(yaw: -12, pitch: 0),
                       HeadOffset(yaw: 0, pitch: 12), HeadOffset(yaw: 0, pitch: -12)] {
            XCTAssertFalse(progress.isComplete)
            for _ in 0..<9 {
                progress.record(offset, at: time)
                time += 1.0 / 30
            }
        }
        XCTAssertTrue(progress.isComplete)
        for direction in HeadSetupDirection.allCases { XCTAssertEqual(progress.fraction(for: direction), 1) }
    }

    func testStillnessAndSmallMovementsDoNotCompleteSetup() {
        var progress = HeadSetupProgress()
        for index in 0..<300 { progress.record(HeadOffset(yaw: 8, pitch: 5), at: Double(index) / 30) }
        XCTAssertTrue(progress.completed.isEmpty)
        XCTAssertLessThan(progress.fraction(for: .left), 1)
    }

    func testSingleSpikesInvalidSamplesAndGapsDoNotCountAsHeldMotion() {
        var progress = HeadSetupProgress()
        progress.record(HeadOffset(yaw: 12, pitch: 0), at: 0)
        progress.record(HeadOffset(yaw: 12, pitch: 0), at: 10)
        progress.record(HeadOffset(yaw: .nan, pitch: 0), at: 10.01)
        progress.record(HeadOffset(yaw: 12, pitch: 0), at: 10.02)
        progress.record(HeadOffset(yaw: 12, pitch: 0), at: 9)
        progress.record(HeadOffset(yaw: 70, pitch: 0), at: 9.01)
        XCTAssertTrue(progress.completed.isEmpty)
        XCTAssertEqual(progress.fraction(for: .left), 0)
    }

    func testCompletedDirectionsRemainCompleteAfterReturningToCenter() {
        var progress = HeadSetupProgress()
        for index in 0..<9 { progress.record(HeadOffset(yaw: 12, pitch: 0), at: Double(index) / 30) }
        progress.record(HeadOffset(yaw: 0, pitch: 0), at: 0.3)
        XCTAssertEqual(progress.completed, [.left])
        XCTAssertFalse(progress.isComplete)
    }
}
