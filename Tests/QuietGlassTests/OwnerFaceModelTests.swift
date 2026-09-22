import XCTest
import CoreML
import CoreVideo
import CoreImage
import ImageIO
import Vision
import ShieldCore
@testable import QuietGlass

final class OwnerFaceModelTests: XCTestCase {
    private func fixtureBuffer(_ name: String) throws -> CVPixelBuffer {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Fixtures/OwnerPoses"))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, image.width, image.height, kCVPixelFormatType_32BGRA,
                                          [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer), kCVReturnSuccess)
        let result = try XCTUnwrap(buffer)
        CIContext().render(CIImage(cgImage: image), to: result)
        return result
    }

    func testCameraPreservesContinuousPoseThroughLandmarkDetection() throws {
        for name in ["center", "left", "right"] {
            let buffer = try fixtureBuffer(name)
            let detector = VNDetectFaceRectanglesRequest()
            detector.revision = VNDetectFaceRectanglesRequestRevision3
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:]).perform([detector])
            let detected = try XCTUnwrap(detector.results?.first)
            let faces = try OwnerFaceDetector.observations(in: buffer)
            XCTAssertEqual(faces.count, 1)
            let face = try XCTUnwrap(faces.first)
            XCTAssertNotNil(face.landmarks)
            XCTAssertNotNil(face.pitch, "Camera head tracking needs a measured pitch")
            XCTAssertTrue(face.pitch?.doubleValue.isFinite == true)
            XCTAssertEqual(try XCTUnwrap(face.yaw).doubleValue, try XCTUnwrap(detected.yaw).doubleValue, accuracy: 0.00001)
            if name == "center" { XCTAssertLessThan(abs(face.yaw!.doubleValue), 0.14) }
            if name == "left" { XCTAssertGreaterThan(face.yaw!.doubleValue, 0.22) }
            if name == "right" { XCTAssertLessThan(face.yaw!.doubleValue, -0.22) }
        }
    }

    func testActualVisionAndModelSamplesCompleteEnrollmentWithoutClosingEyes() throws {
        let model = try OwnerFaceModel()
        func sample(_ name: String) throws -> (vector: [Float], pose: OwnerPose) {
            let buffer = try fixtureBuffer(name)
            let face = try XCTUnwrap(OwnerFaceDetector.observations(in: buffer).first)
            return try XCTUnwrap(model.features(buffer: buffer, face: face))
        }
        let center = try sample("center")
        for (name, positive) in [("left", true), ("right", false)] {
            let turned = try sample(name)
            XCTAssertTrue(turned.pose.isValid)
            var enrollment = OwnerEnrollment(turnPositive: positive)
            var time = 1.0
            for _ in 0..<5 {
                enrollment.observe(vector: center.vector, pose: center.pose, faceCount: 1, at: time)
                time += 0.3
            }
            for _ in 0..<4 {
                enrollment.observe(vector: center.vector, pose: center.pose, faceCount: 1, at: time)
                time += 0.1
            }
            XCTAssertEqual(enrollment.challenge.stage, .turn)
            for _ in 0..<4 {
                enrollment.observe(vector: turned.vector, pose: turned.pose, faceCount: 1, at: time)
                time += 0.1
            }
            XCTAssertEqual(enrollment.vectors.count, 5)
            XCTAssertEqual(enrollment.challenge.stage, .returnToCenter, name)
            for _ in 0..<4 {
                enrollment.observe(vector: center.vector, pose: center.pose, faceCount: 1, at: time)
                time += 0.1
            }
            XCTAssertEqual(enrollment.challenge.stage, .complete, name)
            XCTAssertTrue(enrollment.template?.isValid == true, "A matching turn and look back should finish enrollment")
            XCTAssertEqual(enrollment.progress, 1)
        }
    }

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

extension OwnerFaceModelTests {
    func testMultipleFacesHaveLandmarksAndIndividualPoses() throws {
        let original = try fixtureBuffer("center")
        let source = CIImage(cvPixelBuffer: original)
        let width = CVPixelBufferGetWidth(original), height = CVPixelBufferGetHeight(original)
        var composite: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, width * 2, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &composite), kCVReturnSuccess)
        let buffer = try XCTUnwrap(composite)
        let pair = source.transformed(by: CGAffineTransform(translationX: CGFloat(width), y: 0)).composited(over: source)
        CIContext().render(pair, to: buffer)
        let faces = try OwnerFaceDetector.observations(in: buffer)
        XCTAssertEqual(faces.count, 2)
        let model = try OwnerFaceModel()
        for face in faces {
            XCTAssertNotNil(face.landmarks)
            XCTAssertNotNil(face.pitch)
            XCTAssertNotNil(try model.features(buffer: buffer, face: face))
        }
    }
}
