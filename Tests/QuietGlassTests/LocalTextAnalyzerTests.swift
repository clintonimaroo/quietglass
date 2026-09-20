//  Created by Clinton Imaro on 20/09/2026.

import XCTest
import AppKit
import Vision
import ShieldCore
@testable import QuietGlass

final class LocalTextAnalyzerTests: XCTestCase {
    @MainActor func testVisionFindsSensitiveTextInAnActualRenderedImage() throws {
        let image = NSImage(size: NSSize(width: 1000, height: 300))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1000, height: 300).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 34), .foregroundColor: NSColor.black]
        ("Contact sample@example.test" as NSString).draw(at: NSPoint(x: 40, y: 200), withAttributes: attributes)
        ("Ordinary text stays visible" as NSString).draw(at: NSPoint(x: 40, y: 100), withAttributes: attributes)
        image.unlockFocus()
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        let observations = try XCTUnwrap(request.results)
        let regions = LocalTextAnalyzer.regions(in: observations, options: .emailAddresses)
        XCTAssertEqual(regions.count, 1)
        let region = try XCTUnwrap(regions.first)
        XCTAssertGreaterThan(region.minY, 0.6)
        XCTAssertLessThan(region.width, 0.7)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(region))
        XCTAssertTrue(LocalTextAnalyzer.regions(in: observations, options: .credentials).isEmpty)
    }
}
