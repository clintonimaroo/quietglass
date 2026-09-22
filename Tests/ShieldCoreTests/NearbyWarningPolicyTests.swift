import XCTest
@testable import ShieldCore

final class NearbyWarningPolicyTests: XCTestCase {
    func testTwoMinuteDeadlineDoesNotRestartOnRepeatedUpdates() {
        var policy = NearbyWarningPolicy()
        policy.update(active: true, delay: 120, at: 10)
        XCTAssertEqual(policy.secondsRemaining, 120)
        for time in [11.0, 30, 60, 90, 129.9] {
            policy.update(active: true, delay: 120, at: time)
            XCTAssertFalse(policy.escalated)
        }
        policy.update(active: true, delay: 120, at: 130)
        XCTAssertTrue(policy.escalated)
        XCTAssertEqual(policy.secondsRemaining, 0)
    }

    func testResolvedWarningCancelsAndTheNextWarningGetsItsOwnDeadline() {
        var policy = NearbyWarningPolicy()
        policy.update(active: true, delay: 120, at: 10)
        policy.update(active: false, delay: 120, at: 90)
        XCTAssertNil(policy.secondsRemaining)
        policy.update(active: false, delay: 120, at: 300)
        XCTAssertFalse(policy.escalated)
        policy.update(active: true, delay: 120, at: 301)
        XCTAssertEqual(policy.secondsRemaining, 120)
    }

    func testEditingDelayKeepsTheOriginalStartAndCannotUndoExpiredBlur() {
        var policy = NearbyWarningPolicy()
        policy.update(active: true, delay: 120, at: 10)
        policy.update(active: true, delay: 180, at: 100)
        XCTAssertEqual(policy.secondsRemaining, 90)
        policy.update(active: true, delay: 60, at: 101)
        XCTAssertTrue(policy.escalated)
        policy.update(active: true, delay: 600, at: 102)
        XCTAssertTrue(policy.escalated)
        XCTAssertEqual(policy.secondsRemaining, 0)
    }

    func testDurationBoundsAndInvalidInput() {
        XCTAssertEqual(NearbyWarningPolicy.normalizedDelay(0), 60)
        XCTAssertEqual(NearbyWarningPolicy.normalizedDelay(-60), 60)
        XCTAssertEqual(NearbyWarningPolicy.normalizedDelay(121), 120)
        XCTAssertEqual(NearbyWarningPolicy.normalizedDelay(100_000), 86_400)
        XCTAssertEqual(NearbyWarningPolicy.normalizedDelay(.nan), 120)
        XCTAssertEqual(NearbyWarningPolicy.normalizedDelay(.infinity), 120)
        var policy = NearbyWarningPolicy()
        policy.update(active: true, delay: 120, at: .nan)
        XCTAssertNil(policy.secondsRemaining)
        XCTAssertFalse(policy.escalated)
    }
}
