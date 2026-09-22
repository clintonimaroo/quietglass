import XCTest
import CoreImage
import CoreVideo
import Vision
@testable import QuietGlass

final class PerformanceMeasurementTests: XCTestCase {
    func testMeasurePipelineStages() throws {
        guard ProcessInfo.processInfo.environment["QUIETGLASS_PROFILE"] == "1" else {
            throw XCTSkip("Run with QUIETGLASS_PROFILE=1 to measure local processing costs")
        }
        func buffer(_ image: CIImage) throws -> CVPixelBuffer {
            var result: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferCreate(nil, Int(image.extent.width), Int(image.extent.height), kCVPixelFormatType_32BGRA,
                                               [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &result), kCVReturnSuccess)
            let value = try XCTUnwrap(result); CIContext().render(image, to: value); return value
        }
        func medianMS(_ body: () throws -> Void) rethrows -> Double {
            try body() // warm caches before measuring
            var samples: [Double] = []
            for _ in 0..<7 {
                let start = ProcessInfo.processInfo.systemUptime
                try autoreleasepool { try body() }
                samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            }
            return samples.sorted()[samples.count / 2]
        }
        let faceURL = try XCTUnwrap(Bundle.module.url(forResource: "center", withExtension: "jpg", subdirectory: "Fixtures/OwnerPoses"))
        let face = try buffer(XCTUnwrap(CIImage(contentsOf: faceURL)))
        let previewURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Preview/BlurPreview.png")
        let preview = try XCTUnwrap(CIImage(contentsOf: previewURL))
        let screen = preview.transformed(by: CGAffineTransform(scaleX: 1512 / preview.extent.width, y: 982 / preview.extent.height))
        let pixels = try buffer(screen)
        let model = try OwnerFaceModel()
        let observation = try XCTUnwrap(OwnerFaceDetector.observations(in: face).first)
        let renderer = DisplayBlurRenderer()
        func textScan() throws {
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false; request.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cvPixelBuffer: pixels, options: [:]).perform([request])
        }
        let metrics = [
            "face_detection_ms": try medianMS {
                let request = VNDetectFaceRectanglesRequest()
                try VNImageRequestHandler(cvPixelBuffer: face, orientation: .up).perform([request])
            },
            "owner_landmarks_ms": try medianMS { _ = try OwnerFaceDetector.observations(in: face) },
            "owner_embedding_ms": try medianMS { _ = try model.features(buffer: face, face: observation) },
            "screen_blur_ms": medianMS { _ = renderer.render(screen, radius: 28) },
            "text_scan_ms": try medianMS { try textScan() },
            "unchanged_frame_check_ms": medianMS { _ = FrameFingerprint.digest(pixels) }
        ]
        let json = try JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys])
        print("QUIETGLASS_PROFILE " + String(decoding: json, as: UTF8.self))
    }
}
