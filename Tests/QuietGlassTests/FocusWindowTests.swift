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
}
