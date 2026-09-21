//  Created by Clinton Imaro on 20/09/2026.

import XCTest
@testable import QuietGlass

final class NearbyPeopleTests: XCTestCase {
    @MainActor func testCameraIsOffOnLaunchAndStoppingClearsBothSources() {
        let nearby = NearbyPeople()
        XCTAssertFalse(nearby.enabled)
        XCTAssertFalse(nearby.requesting)
        XCTAssertFalse(nearby.covered)
        var coverage: Bool?
        var monitoring: Bool?
        nearby.onCoverage = { coverage = $0 }
        nearby.onMonitoring = { monitoring = $0 }
        nearby.stop()
        XCTAssertEqual(coverage, false)
        XCTAssertEqual(monitoring, false)
    }
}
