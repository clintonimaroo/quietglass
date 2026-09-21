//  Created by Clinton Imaro on 20/09/2026.

import AppKit
import XCTest
@testable import QuietGlass

final class CaptureVisibilityTests: XCTestCase {
    @MainActor func testHeadBlurCapturePreferenceAppliesBeforeAndAfterSurfaceCreation() throws {
        _ = NSApplication.shared
        let overlay = ShieldOverlay()
        overlay.includeInCaptures = true
        overlay.reconcileScreens()
        defer {
            overlay.clear()
            for surface in overlay.surfaces.values { surface.panel.close() }
        }
        let surface = try XCTUnwrap(overlay.surfaces.values.first)
        let panel = surface.panel
        XCTAssertEqual(panel.sharingType, .readOnly)
        surface.setImage(try sampleImage())
        overlay.includeInCaptures = false
        XCTAssertEqual(panel.sharingType, .none)
        XCTAssertTrue(surface.hasImage)
        overlay.includeInCaptures = true
        XCTAssertEqual(panel.sharingType, .readOnly)
        XCTAssertTrue(overlay.surfaces.values.contains { $0.panel === panel })
        XCTAssertTrue(surface.hasImage)
    }

    @MainActor func testPrivacyCapturePreferencePreservesExistingBlur() throws {
        _ = NSApplication.shared
        let privacy = PrivacyController()
        defer { privacy.shutdown() }
        privacy.includeInCaptures = true
        privacy.screenParametersChanged()
        let surface = try XCTUnwrap(privacy.surfaces.values.first)
        let panel = surface.panel
        XCTAssertEqual(panel.sharingType, .readOnly)
        surface.setImage(try sampleImage())
        privacy.includeInCaptures = false
        XCTAssertEqual(panel.sharingType, .none)
        XCTAssertTrue(surface.hasImage)
        privacy.includeInCaptures = true
        XCTAssertEqual(panel.sharingType, .readOnly)
        XCTAssertTrue(privacy.surfaces.values.contains { $0.panel === panel })
        XCTAssertTrue(surface.hasImage)
    }

    private func sampleImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
                                             bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return try XCTUnwrap(context.makeImage())
    }
}
