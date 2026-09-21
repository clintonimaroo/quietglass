import XCTest
import CoreML
import CoreVideo
import ShieldCore
@testable import QuietGlass

final class OwnerFaceModelTests: XCTestCase {
    func testMissingPackagedModelFailsWithoutDevelopmentFallback() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("MissingModel-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: app) }
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "test.missingmodel", "CFBundlePackageType": "APPL"], format: .xml, options: 0)
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        let bundle = try XCTUnwrap(Bundle(url: app))
        XCTAssertThrowsError(try OwnerFaceModel(bundle: bundle)) { error in
            guard case OwnerModelError.unavailable = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }
    func testBundledModelProducesNormalizedRepeatableEmbeddings() throws {
        let model = try OwnerFaceModel()
        let input = try MLMultiArray(shape: [3,112,112], dataType: .float32)
        for i in 0..<input.count { input[i] = 0 }
        let first = try model.prediction(input), second = try model.prediction(input)
        XCTAssertEqual(first.count, 128)
        XCTAssertTrue(first.allSatisfy(\.isFinite))
        XCTAssertEqual(first.reduce(0) { $0 + $1 * $1 }, 1, accuracy: 0.0001)
        XCTAssertEqual(OwnerTemplate.similarity(first, second), 1, accuracy: 0.00001)
        for i in 0..<input.count { input[i] = 255 }
        let white = try model.prediction(input)
        XCTAssertLessThan(OwnerTemplate.similarity(first, white), 0.99)
    }

    func testAlignmentAndPixelsKeepRGBChannelsAndTopLeftOrientation() throws {
        let canonical = [CGPoint(x: 38.2946, y: 51.6963), CGPoint(x: 73.5318, y: 51.5014),
                         CGPoint(x: 56.0252, y: 71.7366), CGPoint(x: 41.5493, y: 92.3655), CGPoint(x: 70.7299, y: 92.2041)]
        let transform = try XCTUnwrap(OwnerFaceModel.alignment(canonical.map { CGPoint(x: $0.x*2+30, y: $0.y*2+40) }))
        for p in canonical {
            let actual = CGPoint(x: p.x*2+30, y: p.y*2+40).applying(transform)
            XCTAssertEqual(actual.x, p.x, accuracy: 0.001)
            XCTAssertEqual(actual.y, p.y, accuracy: 0.001)
        }
        XCTAssertNil(OwnerFaceModel.alignment(Array(repeating: .zero, count: 5)))
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 112, 112, kCVPixelFormatType_32BGRA,
                                          [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer), kCVReturnSuccess)
        let b = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(b, [])
        let bytes = CVPixelBufferGetBaseAddress(b)!.assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(b)
        for y in 0..<112 {
            for x in 0..<112 {
                let p = y * rowBytes + x * 4
                bytes[p] = y >= 56 ? 255 : 0 // blue bottom
                bytes[p+1] = 0
                bytes[p+2] = y < 56 ? 255 : 0 // red top
                bytes[p+3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(b, [])
        let input = try OwnerFaceModel().alignedInput(buffer: b, topLeftTransform: .identity)
        XCTAssertEqual(input[[0, 10, 50] as [NSNumber]].floatValue, 255, accuracy: 1)
        XCTAssertEqual(input[[2, 10, 50] as [NSNumber]].floatValue, 0, accuracy: 1)
        XCTAssertEqual(input[[0, 100, 50] as [NSNumber]].floatValue, 0, accuracy: 1)
        XCTAssertEqual(input[[2, 100, 50] as [NSNumber]].floatValue, 255, accuracy: 1)
    }
}
