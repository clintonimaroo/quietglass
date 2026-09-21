//  Created by Clinton Imaro on 20/09/2026.

import XCTest
@testable import ShieldCore

final class NearbyPresenceTests: XCTestCase {
    func testBriefSecondFaceDoesNotFlashBlur() {
        var state = NearbyPresence()
        XCTAssertFalse(state.observe(faceCount: 2, at: 1))
        XCTAssertFalse(state.observe(faceCount: 2, at: 1.2))
        XCTAssertFalse(state.observe(faceCount: 1, at: 1.4))
        XCTAssertFalse(state.observe(faceCount: 2, at: 1.6))
        XCTAssertTrue(state.observe(faceCount: 2, at: 2))
    }

    func testNoFacesAndMissingFramesNeverReleaseProtection() {
        var state = NearbyPresence()
        state.observe(faceCount: 2, at: 1)
        XCTAssertTrue(state.observe(faceCount: 2, at: 1.4))
        XCTAssertTrue(state.observe(faceCount: 0, at: 2))
        XCTAssertTrue(state.observe(faceCount: 0, at: 20))
        XCTAssertTrue(state.observe(faceCount: 1, at: 21))
        XCTAssertTrue(state.observe(faceCount: 1, at: 25))
        XCTAssertTrue(state.observe(faceCount: 1, at: 25.8))
        XCTAssertFalse(state.observe(faceCount: 1, at: 26.6))
    }

    func testOneFaceNeverTriggersAndOldSamplesAreIgnored() {
        var state = NearbyPresence()
        for index in 0...100 { XCTAssertFalse(state.observe(faceCount: 1, at: Double(index))) }
        XCTAssertFalse(state.observe(faceCount: 2, at: 10))
        XCTAssertFalse(state.observe(faceCount: 2, at: .nan))
        XCTAssertFalse(state.observe(faceCount: -1, at: 101))
    }

    func testPublicProfileActuallyStrengthensProtection() {
        XCTAssertLessThan(PrivacyProfile.publicSpace.settings.comfort, PrivacyProfile.office.settings.comfort)
        XCTAssertLessThan(PrivacyProfile.publicSpace.settings.transition, PrivacyProfile.office.settings.transition)
        XCTAssertGreaterThan(PrivacyProfile.publicSpace.settings.blur, PrivacyProfile.office.settings.blur)
    }
}
