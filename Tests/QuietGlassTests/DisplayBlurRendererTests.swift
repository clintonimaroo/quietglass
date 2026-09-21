//  Created by Clinton Imaro on 20/09/2026.

import XCTest
import CoreImage
@testable import QuietGlass

final class DisplayBlurRendererTests: XCTestCase {
    private func pixels(_ image: CGImage) -> [UInt8] {
        let context = CIContext()
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        context.render(CIImage(cgImage: image), toBitmap: &bytes, rowBytes: image.width * 4,
                       bounds: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return bytes
    }

    func testTransparentTransitionFrameRetainsPreviousBlur() throws {
        let renderer = DisplayBlurRenderer()
        let bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: bounds)
        let first = try XCTUnwrap(renderer.render(red, radius: 0))
        let empty = CIImage(color: .clear).cropped(to: bounds)
        let retained = try XCTUnwrap(renderer.render(empty, radius: 20))
        XCTAssertEqual(pixels(first), pixels(retained))
    }

    func testFirstTransparentFrameAndResolutionChangeStayOpaque() throws {
        let renderer = DisplayBlurRenderer()
        for size in [4, 16] {
            let empty = CIImage(color: .clear).cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
            let image = try XCTUnwrap(renderer.render(empty, radius: 0))
            let bytes = pixels(image)
            XCTAssertEqual(image.width, size)
            for index in stride(from: 3, to: bytes.count, by: 4) { XCTAssertEqual(bytes[index], 255) }
        }
    }
}
