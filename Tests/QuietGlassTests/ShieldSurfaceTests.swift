// Clinton Imaro was here 20/09/2026.

import XCTest
import AppKit
@testable import QuietGlass

final class ShieldSurfaceTests: XCTestCase {
    @MainActor func testNewDisplayHasTemporaryCoverageBeforeFirstCapture() throws {
        _ = NSApplication.shared
        let surface = ShieldSurface(screen: try XCTUnwrap(NSScreen.screens.first))
        defer { surface.panel.close() }
        surface.resize(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        surface.update(coverage: 1, direction: .left)
        XCTAssertTrue(surface.panel.isVisible)
        XCTAssertNotNil(surface.panel.contentView?.layer?.backgroundColor)
        XCTAssertFalse(surface.hasImage)
        surface.update(coverage: 0, direction: .left)
        surface.keepVisible()
        XCTAssertFalse(surface.panel.isVisible, "A display with zero coverage must stay clear during refresh")
        surface.clear(); XCTAssertFalse(surface.panel.isVisible)
    }
    @MainActor func testGeometryChangesRetainWindowAndPixels() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let surface = ShieldSurface(screen: screen)
        defer { surface.panel.close() }
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
                                             bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        surface.setImage(try XCTUnwrap(context.makeImage()))
        let panel = surface.panel
        surface.resize(to: screen.frame)
        surface.resize(to: CGRect(x: -1600, y: 100, width: 1600, height: 900))
        XCTAssertTrue(surface.panel === panel)
        XCTAssertTrue(surface.hasImage, "Changing display geometry must not expose a clear frame")
        XCTAssertEqual(surface.panel.frame.width, 1600)
        XCTAssertEqual(surface.panel.frame.height, 900)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllApplications))
        XCTAssertTrue(panel.collectionBehavior.contains(.stationary))
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertFalse(panel.hidesOnDeactivate)
        surface.clear()
        XCTAssertFalse(surface.hasImage)
    }
}
