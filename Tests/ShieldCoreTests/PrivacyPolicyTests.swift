//  Created by Clinton Imaro on 20/09/2026.

import XCTest
@testable import ShieldCore

final class PrivacyPolicyTests: XCTestCase {
    func testExistingAppRulesMigrateWithoutEnablingAutomaticProtection() throws {
        let data = Data("{\"bundleID\":\"example.editor\",\"name\":\"Editor\",\"mode\":\"stronger\"}".utf8)
        let rule = try JSONDecoder().decode(AppPrivacyRule.self, from: data)
        XCTAssertEqual(rule.mode, .stronger); XCTAssertFalse(rule.protectWindows)
    }

    func testSavedAreasMatchOnlyExactAppAndWindowWithoutSavingTheTitle() throws {
        let area = SavedWindowArea(bundleID: "example.editor", appName: "Editor", windowTitle: "Private project", rectangle: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        let data = try JSONEncoder().encode(area)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Private project"))
        let restored = try JSONDecoder().decode(SavedWindowArea.self, from: data)
        XCTAssertTrue(restored.matches(bundleID: "example.editor", windowTitle: "Private project"))
        XCTAssertFalse(restored.matches(bundleID: "another.editor", windowTitle: "Private project"))
        XCTAssertFalse(restored.matches(bundleID: "example.editor", windowTitle: "Different project"))
        XCTAssertFalse(restored.matches(bundleID: "example.editor", windowTitle: ""))
        XCTAssertFalse(SavedWindowArea(bundleID: "example.editor", appName: "Editor", windowTitle: "Window", rectangle: CGRect(x: -1, y: 0, width: 2, height: 1)).isValid)
    }
    func testStrongerRuleNeverWeakensExistingSettings() {
        for comfort in [2.0, 8, 15, 30] {
            for transition in [5.0, 18, 30] {
                for blur in [10.0, 28, 70] {
                    let result = AppProtectionMode.stronger.settings(comfort: comfort, transition: transition, blur: blur)
                    XCTAssertLessThanOrEqual(result.comfort, comfort)
                    XCTAssertLessThanOrEqual(result.transition, transition)
                    XCTAssertGreaterThanOrEqual(result.blur, blur)
                }
            }
        }
    }

    func testRulesRoundTripWithoutChangingIdentityOrSettings() throws {
        let rules = [AppPrivacyRule(bundleID: "com.example.editor", name: "Editor", mode: .pause),
                     AppPrivacyRule(bundleID: "com.example.mail", name: "Mail", mode: .stronger)]
        XCTAssertEqual(try JSONDecoder().decode([AppPrivacyRule].self, from: JSONEncoder().encode(rules)), rules)
        let result = AppProtectionMode.standard.settings(comfort: 23, transition: 17, blur: 28)
        XCTAssertEqual(result.comfort, 23)
        XCTAssertEqual(result.transition, 17)
        XCTAssertEqual(result.blur, 28)
    }

    func testCalibrationIgnoresRareOutliersAndAddsRoomForMovement() {
        var calibration = AdaptiveCalibration()
        for _ in 0..<180 { calibration.record(angle: 5.2) }
        for _ in 0..<4 { calibration.record(angle: 90) }
        for _ in 0..<4 { calibration.record(angle: 20) }
        XCTAssertEqual(calibration.recommendation, 9)
    }

    func testCalibrationRejectsInsufficientOrUnreliableInput() {
        var calibration = AdaptiveCalibration()
        for _ in 0..<59 { calibration.record(angle: 2) }
        XCTAssertNil(calibration.recommendation)
        for _ in 0..<30 { calibration.record(angle: .nan) }
        for _ in 0..<20 { calibration.record(angle: 2) }
        XCTAssertNil(calibration.recommendation)
    }

    func testCalibrationHasConservativeLimits() {
        var still = AdaptiveCalibration()
        var wide = AdaptiveCalibration()
        for _ in 0..<100 { still.record(angle: 0); wide.record(angle: 25) }
        XCTAssertEqual(still.recommendation, 6)
        XCTAssertEqual(wide.recommendation, 25)
    }

    func testWindowOcclusionProducesOnlyVisibleDisjointRegions() {
        let window = CGRect(x: -800, y: 100, width: 600, height: 400)
        let foreground = CGRect(x: -600, y: 200, width: 100, height: 200)
        let regions = ScreenRegions.visible(window, behind: [foreground])
        XCTAssertEqual(regions.reduce(0) { $0 + $1.width * $1.height }, 220_000)
        for (index, region) in regions.enumerated() {
            XCTAssertTrue(window.contains(region))
            XCTAssertTrue(region.intersection(foreground).isEmpty)
            for other in regions.dropFirst(index + 1) { XCTAssertTrue(region.intersection(other).isEmpty) }
        }
        XCTAssertTrue(ScreenRegions.visible(window, behind: [window]).isEmpty)
        XCTAssertEqual(ScreenRegions.visible(window, behind: [.zero]), [window])
    }

    func testOverlappingOccludersDoNotSubtractTwice() {
        let window = CGRect(x: 0, y: 0, width: 100, height: 100)
        let regions = ScreenRegions.visible(window, behind: [CGRect(x: 0, y: 0, width: 60, height: 100),
                                                            CGRect(x: 40, y: 0, width: 40, height: 100)])
        XCTAssertEqual(regions.reduce(0) { $0 + $1.width * $1.height }, 2_000)
    }

    func testVisionCoordinatesRespectDisplayOriginAndClipAtEdges() {
        let screen = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        XCTAssertEqual(ScreenRegions.fromVision(CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25), in: screen),
                       CGRect(x: -1440, y: 740, width: 960, height: 270))
        XCTAssertEqual(ScreenRegions.fromVision(CGRect(x: -0.1, y: -0.1, width: 1.2, height: 1.2), in: screen), screen)
    }
}
