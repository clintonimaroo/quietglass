//  Created by Clinton Imaro on 20/09/2026.

import XCTest
import AppKit
@testable import QuietGlass

final class ShieldSurfaceTests: XCTestCase {
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
        surface.clear()
        XCTAssertFalse(surface.hasImage)
    }
}
