//  Created by Clinton Imaro on 20/09/2026.

import XCTest
import AppKit
@testable import QuietGlass

final class PrivacySurfaceTests: XCTestCase {
    @MainActor func testNewSurfaceLaysOutImageAndMaskWithoutAResize() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let surface = PrivacySurface(screen: screen)
        defer { surface.panel.close() }
        let layer = try XCTUnwrap(surface.panel.contentView?.layer?.sublayers?.first)
        XCTAssertEqual(layer.frame.size, screen.frame.size)
        XCTAssertEqual(layer.mask?.frame.size, screen.frame.size)
    }

    @MainActor func testFullScreenCoversUntilFirstFrameThenUsesCapturedPixelsAndAllowsPeek() throws {
        _ = NSApplication.shared
        let surface = PrivacySurface(screen: try XCTUnwrap(NSScreen.screens.first))
        defer { surface.panel.close() }
        XCTAssertTrue(surface.panel.isFloatingPanel)
        XCTAssertTrue(surface.panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(surface.panel.collectionBehavior.contains(.canJoinAllApplications))
        XCTAssertFalse(surface.panel.hidesOnDeactivate)
        surface.resize(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        surface.update(windows: [], sensitive: [], fullScreen: true)
        XCTAssertTrue(surface.panel.isVisible, "New displays must stay covered while their first frame loads")
        XCTAssertFalse(surface.hasImage)
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
                                             bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        surface.setImage(try XCTUnwrap(context.makeImage()))
        surface.update(windows: [], sensitive: [], fullScreen: true)
        XCTAssertTrue(surface.panel.isVisible)
        let layers = try XCTUnwrap(surface.panel.contentView?.layer?.sublayers)
        XCTAssertEqual(layers.count, 1)
        XCTAssertNotNil(layers[0].contents)
        XCTAssertNil(layers[0].backgroundColor)
        surface.update(windows: [], sensitive: [], fullScreen: true, peeking: true)
        XCTAssertFalse(surface.panel.isVisible)
        surface.update(windows: [], sensitive: [], fullScreen: true)
        XCTAssertTrue(surface.panel.isVisible)
        surface.clear()
        XCTAssertFalse(surface.panel.isVisible)
    }

    @MainActor func testWindowAndTextUseTheSameBlurMask() throws {
        _ = NSApplication.shared
        let surface = PrivacySurface(screen: try XCTUnwrap(NSScreen.screens.first))
        defer { surface.panel.close() }
        surface.resize(to: CGRect(x: 100, y: 100, width: 4, height: 4))
        surface.update(windows: [CGRect(x: 100, y: 100, width: 2, height: 2)],
                       sensitive: [CGRect(x: 102, y: 102, width: 2, height: 2)], fullScreen: false)
        let layers = try XCTUnwrap(surface.panel.contentView?.layer?.sublayers)
        let mask = try XCTUnwrap(layers[0].mask as? CAShapeLayer)
        XCTAssertEqual(mask.path?.boundingBox, CGRect(x: 0, y: 0, width: 4, height: 4))
        XCTAssertNotNil(layers[0].backgroundColor, "Selected regions have temporary coverage before capture is ready")
        surface.update(windows: [], sensitive: [], fullScreen: false)
        XCTAssertFalse(surface.panel.isVisible)
    }

    @MainActor func testScreenParameterChangesPreserveExistingBlurPixels() throws {
        _ = NSApplication.shared
        let controller = PrivacyController()
        defer { controller.shutdown() }
        controller.screenParametersChanged()
        let surface = try XCTUnwrap(controller.surfaces.values.first)
        let panel = surface.panel
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
                                             bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        surface.setImage(try XCTUnwrap(context.makeImage()))
        controller.screenParametersChanged()
        controller.screenParametersChanged()
        XCTAssertTrue(controller.surfaces.values.contains { $0.panel === panel })
        XCTAssertTrue(surface.hasImage, "Work-area changes must not clear a captured blur frame")
    }
}
