//  Created by Clinton Imaro on 20/09/2026.

import XCTest
import AppKit
import SwiftUI
@testable import QuietGlass

final class HeadSetupPanelTests: XCTestCase {
    @MainActor func testHostingControllerCannotCollapseSetupWindowToZeroSize() throws {
        _ = NSApplication.shared
        let panel = HeadSetupPanel()
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let content = NSHostingController(rootView: Text("Head tracking").frame(width: 420, height: 520))
        content.sizingOptions = []
        panel.installContent(content)
        panel.contentView?.layoutSubtreeIfNeeded()
        let bounds = try XCTUnwrap(panel.contentView?.bounds)
        XCTAssertEqual(bounds.width, 420, accuracy: 1)
        XCTAssertEqual(bounds.height, 520, accuracy: 1)
        XCTAssertGreaterThan(panel.frame.height, 520)
        XCTAssertEqual(panel.contentMinSize, panel.contentMaxSize)
    }
}
