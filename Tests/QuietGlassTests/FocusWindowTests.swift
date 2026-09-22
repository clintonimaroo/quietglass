import AppKit
import XCTest
import ShieldCore
@testable import QuietGlass

@MainActor
final class FocusWindowTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 900)
    private let settings = CGRect(x: 80, y: 80, width: 1040, height: 760)
    private let active = CGRect(x: 100, y: 160, width: 440, height: 500)
    private let background = CGRect(x: 660, y: 160, width: 400, height: 500)

    private func window(_ frame: CGRect, pid: pid_t, layer: Int = 0, alpha: Double = 1) -> [String: Any] {
        [kCGWindowOwnerPID as String: NSNumber(value: pid), kCGWindowLayer as String: layer,
         kCGWindowAlpha as String: alpha,
         kCGWindowBounds as String: CGRect(x: frame.minX, y: screen.maxY - frame.maxY, width: frame.width, height: frame.height).dictionaryRepresentation]
    }

    func testSettingsBehindOtherAppsCannotKeepTheirBackgroundWindowsClear() {
        let items = [window(screen, pid: 1, layer: 1002), window(active, pid: 2),
                     window(background, pid: 3), window(settings, pid: 1)]
        let controls = PrivacyController.visibleControlRegions(in: items, appPID: 1, desktopTop: screen.maxY)
        let blur = ScreenRegions.visible(screen, behind: controls + [active])
        XCTAssertTrue(blur.contains { $0.contains(CGPoint(x: background.midX, y: background.midY)) },
                      "A background app covering Settings must still blur")
        XCTAssertFalse(blur.contains { $0.contains(CGPoint(x: active.midX, y: active.midY)) })
        XCTAssertFalse(blur.contains { $0.contains(CGPoint(x: 90, y: 90)) }, "Visible Settings controls stay usable")
    }

    func testForegroundSettingsStayClearAndOwnOverlayDoesNotOccludeControls() {
        let items = [window(screen, pid: 1, layer: 1002), window(settings, pid: 1), window(background, pid: 3)]
        let controls = PrivacyController.visibleControlRegions(in: items, appPID: 1, desktopTop: screen.maxY)
        XCTAssertEqual(controls, [settings])
    }

    func testTransparentControlWindowsDoNotPunchHolesInFocus() {
        let items = [window(screen, pid: 2, alpha: 0), window(settings, pid: 1, alpha: 0)]
        XCTAssertTrue(PrivacyController.visibleControlRegions(in: items, appPID: 1, desktopTop: screen.maxY).isEmpty)
    }

    func testCursorHelperWindowsCannotPaintWallpaperOverSettings() {
        // The live cursor helper reports alpha 1 for a transparent 126-point
        // window. Treating its bounding box as opaque produced a blur square.
        let cursor = CGRect(x: 693, y: 378, width: 126, height: 126)
        for bundle in ["com.openai.sky.CUAService", "com.apple.TextInputUI.xpc.CursorUIViewService"] {
            let items = [window(screen, pid: 1, layer: 1002), window(cursor, pid: 4),
                         window(settings, pid: 1), window(background, pid: 3)]
            let content = PrivacyController.contentWindowItems(in: items, bundleIdentifiers: [4: bundle])
            let controls = PrivacyController.visibleControlRegions(in: content, appPID: 1, desktopTop: screen.maxY)
            let blur = ScreenRegions.visible(screen, behind: controls)
            XCTAssertEqual(controls, [settings], bundle)
            XCTAssertFalse(blur.contains { $0.contains(CGPoint(x: cursor.midX, y: cursor.midY)) }, bundle)
        }
    }

    func testRealUtilityWindowsStillOccludeSettings() {
        let items = [window(background, pid: 3), window(settings, pid: 1)]
        let content = PrivacyController.contentWindowItems(in: items, bundleIdentifiers: [3: "example.utility"])
        let controls = PrivacyController.visibleControlRegions(in: content, appPID: 1, desktopTop: screen.maxY)
        let blur = ScreenRegions.visible(screen, behind: controls)
        XCTAssertTrue(blur.contains { $0.contains(CGPoint(x: background.midX, y: background.midY)) })
    }

    func testDockAndCursorDecorationsDoNotHideProtectedContent() {
        let cursor = CGRect(x: background.midX, y: background.midY, width: 126, height: 126)
        let items = [window(screen, pid: 5, layer: 20), window(cursor, pid: 4), window(background, pid: 3)]
        let content = PrivacyController.contentWindowItems(in: items, bundleIdentifiers: [5: "com.apple.dock", 4: "com.openai.sky.CUAService"])
        XCTAssertEqual(content.count, 1)
        XCTAssertEqual((content.first?[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, 3)
    }

    func testAutomaticAppProtectionRespectsForegroundWindowsAndSettings() {
        let items = [window(active, pid: 2), window(background, pid: 3), window(settings, pid: 1)]
        let regions = PrivacyController.automaticRegions(in: items,
            rules: [AppPrivacyRule(bundleID: "example.private", name: "Private", protectWindows: true)], savedAreas: [],
            bundleIdentifiers: [2: "example.public", 3: "example.private"], appPID: 1, desktopTop: screen.maxY)
        XCTAssertEqual(regions, [background])
        XCTAssertFalse(regions.contains { $0.contains(CGPoint(x: active.midX, y: active.midY)) })
        let coveredItems = [window(settings, pid: 1), window(background, pid: 3)]
        XCTAssertTrue(PrivacyController.automaticRegions(in: coveredItems,
            rules: [AppPrivacyRule(bundleID: "example.private", name: "Private", protectWindows: true)], savedAreas: [],
            bundleIdentifiers: [3: "example.private"], appPID: 1, desktopTop: screen.maxY).isEmpty)
    }

    func testRememberedAreaFollowsMatchingWindowAcrossDisplayOriginsAndSizes() {
        let normalized = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.2)
        let saved = SavedWindowArea(bundleID: "example.private", appName: "Private", windowTitle: "A document", rectangle: normalized)
        for frame in [background, CGRect(x: -1600, y: 100, width: 1200, height: 700)] {
            var item = window(frame, pid: 3)
            item[kCGWindowName as String] = "A document"
            let regions = PrivacyController.automaticRegions(in: [item], rules: [], savedAreas: [saved],
                bundleIdentifiers: [3: "example.private"], appPID: 1, desktopTop: screen.maxY)
            XCTAssertEqual(regions, [ScreenRegions.fromVision(normalized, in: frame)])
            item[kCGWindowName as String] = "Different document"
            XCTAssertTrue(PrivacyController.automaticRegions(in: [item], rules: [], savedAreas: [saved],
                bundleIdentifiers: [3: "example.private"], appPID: 1, desktopTop: screen.maxY).isEmpty)
        }
    }
}
