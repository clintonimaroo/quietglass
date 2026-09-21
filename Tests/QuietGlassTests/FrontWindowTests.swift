//  Created by Clinton Imaro on 20/09/2026.

import AppKit
import XCTest
@testable import QuietGlass

@MainActor
final class FrontWindowTests: XCTestCase {
    func testChromeFullScreenToolbarStripsDoNotReplaceContentWindow() {
        let windows = [window(1, width: 1512, height: 41), window(2, width: 1512, height: 81),
                       window(3, width: 1512, height: 158), window(4, width: 1512, height: 827)]
        XCTAssertEqual(PrivacyController.frontWindowItem(in: windows, for: 123)?[kCGWindowNumber as String] as? Int, 4)
    }

    func testFrontmostCompactWindowWinsOverLargerWindowBehindIt() {
        let windows = [window(1, width: 320, height: 180), window(2, width: 1100, height: 850)]
        XCTAssertEqual(PrivacyController.frontWindowItem(in: windows, for: 123)?[kCGWindowNumber as String] as? Int, 1)
        XCTAssertNil(PrivacyController.frontWindowItem(in: windows, for: 456))
    }

    private func window(_ id: Int, width: CGFloat, height: CGFloat) -> [String: Any] {
        [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: NSNumber(value: 123),
         kCGWindowLayer as String: NSNumber(value: 0), kCGWindowAlpha as String: 1.0,
         kCGWindowBounds as String: CGRect(x: 0, y: 33, width: width, height: height).dictionaryRepresentation]
    }
}
