import XCTest
import CoreVideo
@testable import QuietGlass

final class FrameFingerprintTests: XCTestCase {
    func testAnyChangedPixelInvalidatesTheTextScanCache() throws {
        var value: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 17, 13, kCVPixelFormatType_32BGRA, nil, &value), kCVReturnSuccess)
        let buffer = try XCTUnwrap(value)
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        memset(base, 0, stride * 13)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let original = try XCTUnwrap(FrameFingerprint.digest(buffer))
        XCTAssertEqual(original, FrameFingerprint.digest(buffer))
        for (x, y) in [(0, 0), (16, 12), (7, 5)] {
            CVPixelBufferLockBaseAddress(buffer, [])
            base.storeBytes(of: UInt8(255), toByteOffset: y * stride + x * 4, as: UInt8.self)
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertNotEqual(original, FrameFingerprint.digest(buffer))
            CVPixelBufferLockBaseAddress(buffer, [])
            base.storeBytes(of: UInt8(0), toByteOffset: y * stride + x * 4, as: UInt8.self)
            CVPixelBufferUnlockBaseAddress(buffer, [])
        }
        XCTAssertEqual(original, FrameFingerprint.digest(buffer))
    }
}
